#!/usr/bin/env bash
# shellcheck disable=SC2034  # variables defined here are used by the scripts that source it
# Terraform helpers for the optional EKS cluster (same conventions as the other
# AWS projects: state in the aws-foundation S3 bucket). Source after lib.sh.
TF_EKS="$REPO_ROOT/infra/eks"
EKS_CTX="kubeops-eks"

aws_account_id() { aws sts get-caller-identity --query Account --output text; }

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
