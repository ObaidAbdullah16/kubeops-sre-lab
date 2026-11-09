#!/usr/bin/env bash
# shellcheck disable=SC2034  # variables defined here are used by the scripts that source it
# Terraform helpers for the optional EKS cluster (same conventions as the other
# AWS projects: state in the aws-foundation S3 bucket). Source after lib.sh.
TF_EKS="$REPO_ROOT/infra/eks"
EKS_CTX="kubeops-eks"

aws_account_id() { aws sts get-caller-identity --query Account --output text; }

# ---- AWS Free plan and vCPU quota (EKS demo day) ----------------------------------
# Accounts from the new AWS sign-up start on the Free plan (credits only). Until the account is
# upgraded to the Paid plan, EC2 only starts instance types marked "Free tier eligible"
# (t3/t4g .micro and .small, c7i-flex.large, m7i-flex.large) and refuses every other type with
# "The specified instance type is not eligible for Free Tier".
aws_free_plan() {
  local plan="" r
  for r in "$AWS_REGION" us-east-1; do
    plan="$(aws freetier get-account-plan-state --region "$r" --query accountPlanType --output text 2>/dev/null)" && break
  done
  case "$plan" in
    FREE) return 0 ;;
    PAID) return 1 ;;
    *) [[ "${AWS_ACCOUNT_TYPE:-classic}" == project ]] ;;   # unknown: a new sign-up may still be on it
  esac
}

# require_launchable <instance type> <count> : stop before Terraform creates anything (the EKS
# control plane costs $0.10/hour) when this account cannot start <count> nodes of that type.
require_launchable() {
  local type="$1" count="$2" eligible vcpus quota
  if aws_free_plan; then
    if eligible="$(aws ec2 describe-instance-types --region "$AWS_REGION" --instance-types "$type" \
          --filters Name=free-tier-eligible,Values=true --query 'InstanceTypes[0].InstanceType' --output text 2>/dev/null)" \
        && [[ "$eligible" != "$type" ]]; then
      die "$type cannot start in this account: it is on the AWS Free plan, which only starts these types: $(aws ec2 describe-instance-types --region "$AWS_REGION" --filters Name=free-tier-eligible,Values=true --query 'InstanceTypes[].InstanceType' --output text 2>/dev/null | tr '\t' ' '). Upgrade the account to the Paid plan (Billing and Cost Management > Free plan; unused credits keep applying) or use the free kind lab."
    fi
  fi
  vcpus="$(aws ec2 describe-instance-types --region "$AWS_REGION" --instance-types "$type" --query 'InstanceTypes[0].VCpuInfo.DefaultVCpus' --output text 2>/dev/null || true)"
  quota="$(aws service-quotas get-service-quota --region "$AWS_REGION" --service-code ec2 --quota-code L-1216C47A --query 'Quota.Value' --output text 2>/dev/null || true)"
  quota="${quota%%.*}"
  if [[ "$vcpus" =~ ^[0-9]+$ && "$quota" =~ ^[0-9]+$ ]] && (( vcpus * count > quota )); then
    die "$count x $type need $((vcpus * count)) vCPUs, but this account may only run $quota vCPUs of standard instances at once. Ask for more: Service Quotas > Amazon EC2 > 'Running On-Demand Standard (A, C, D, H, I, M, R, T, Z) instances' > Request increase (8 is plenty), then run this again."
  fi
}

state_bucket() { echo "${TF_STATE_BUCKET:-tfstate-$(aws_account_id)-${AWS_REGION}}"; }

# tf_init <terraform dir> <state key>
tf_init() {
  local dir="$1" key="$2" bucket
  bucket="$(state_bucket)"
  aws s3api head-bucket --bucket "$bucket" >/dev/null 2>&1 \
    || die "State bucket $bucket not found: the AWS foundation is not set up (or you are logged in to another account). Start it first: bash _setup/projects.sh up foundation"
  terraform -chdir="$dir" init -input=false -reconfigure \
    -backend-config="bucket=${bucket}" \
    -backend-config="key=${key}" \
    -backend-config="region=${AWS_REGION}" \
    -backend-config="use_lockfile=true" \
    -backend-config="encrypt=true" >/dev/null
  # A run that lost its AWS login half-way leaves errored.tfstate behind: upload it first, or
  # Terraform would work from the older state in S3.
  if [[ -f "$dir/errored.tfstate" ]]; then
    printf '[state] Uploading the state an interrupted run could not save (errored.tfstate)\n' >&2
    if terraform -chdir="$dir" state push errored.tfstate; then
      mv "$dir/errored.tfstate" "$dir/errored.tfstate.uploaded-$(date +%Y%m%d-%H%M%S)"
    else
      printf '[state] Could not upload %s/errored.tfstate - if the state is locked, see the guide: "Error acquiring the state lock"\n' "$dir" >&2
      return 1
    fi
  fi
}

tf_apply() { # tf_apply <dir> [extra args...]
  local dir="$1"; shift
  if [[ "$AUTO_APPROVE" == "1" ]]; then
    terraform -chdir="$dir" apply -input=false -auto-approve -var "aws_region=${AWS_REGION}" "$@"
  else
    terraform -chdir="$dir" apply -input=false -var "aws_region=${AWS_REGION}" "$@"
  fi
}

tf_destroy() { # tf_destroy <dir> [extra args...]
  local dir="$1"; shift
  if [[ "$AUTO_APPROVE" == "1" ]]; then
    terraform -chdir="$dir" destroy -input=false -auto-approve -var "aws_region=${AWS_REGION}" "$@"
  else
    terraform -chdir="$dir" destroy -input=false -var "aws_region=${AWS_REGION}" "$@"
  fi
}

tf_out() { terraform -chdir="$1" output -raw "$2" 2>/dev/null || true; }

# Is anything in this Terraform state? (used by status / auto-stop)
tf_has_resources() { [[ -n "$(terraform -chdir="$1" state list 2>/dev/null | grep -v '^data\.' || true)" ]]; }
