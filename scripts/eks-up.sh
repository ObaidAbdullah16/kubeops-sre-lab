#!/usr/bin/env bash
# Optional demo day on AWS: create an EKS cluster with 2 nodes and deploy the same GitOps stack
# as the kind lab. ~20 minutes. Nodes and cost while up:
#   classic account                      2 x Graviton spot (t4g.medium/large)  ~$0.15/hour
#   project account (new AWS sign-up)    2 x t4g.medium on-demand (no spot)    ~$0.20/hour
#   ... still on the AWS Free plan       2 x c7i-flex.large (Intel)            ~$0.35/hour
# The Free plan only starts "Free tier eligible" types; c7i-flex.large is the smallest of them
# with room for this stack (t4g.small: 2 GB and 11 pods per node is too little).
# Stop with: bash scripts/eks-down.sh   (in a classic account the nightly Auto-stop workflow also does it)
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=tf.sh
source "$(dirname "${BASH_SOURCE[0]}")/tf.sh"
need aws terraform kubectl helm git curl

myip="$(curl -fsS -m 5 https://checkip.amazonaws.com | tr -d '[:space:]' || true)"
cidrs='["0.0.0.0/0"]'
if [[ "${EKS_OPEN_API:-0}" != "1" && "$myip" =~ ^[0-9.]+$ ]]; then
  cidrs="[\"$myip/32\"]"
  log "Kubernetes API will only accept connections from $myip (EKS_OPEN_API=1 to allow all)"
fi

# Extra cluster admins (comma-separated IAM ARNs), e.g. your SSO role when CI creates the cluster.
admins="[]"
if [[ -n "${EKS_ADMIN_ARNS:-}" ]]; then
  admins="[$(tr ',' '\n' <<<"$EKS_ADMIN_ARNS" | sed '/^ *$/d; s/^ *//; s/ *$//; s/.*/"&"/' | paste -sd, -)]"
fi

nodes=()
cost="~\$0.15/hour"
node_desc="2 x Graviton spot (t4g.medium/t4g.large)"
if [[ "${AWS_ACCOUNT_TYPE:-classic}" == project ]]; then
  if aws_free_plan; then
    node_type=c7i-flex.large; cost="~\$0.35/hour"
    nodes=(-var "capacity_type=ON_DEMAND" -var "node_instance_types=[\"$node_type\"]" -var "node_ami_type=AL2023_x86_64_STANDARD")
  else
    node_type=t4g.medium; cost="~\$0.20/hour"
    nodes=(-var "capacity_type=ON_DEMAND" -var "node_instance_types=[\"$node_type\"]")
  fi
  node_desc="2 x $node_type on-demand"
  require_launchable "$node_type" 2
fi
log "Nodes: $node_desc - $cost while up"
log "Terraform apply: VPC, EKS control plane, node group (~15 minutes)"
tf_init "$TF_EKS" "kubeops-sre-lab/eks.tfstate"
tf_apply "$TF_EKS" -var "api_allowed_cidrs=$cidrs" -var "admin_principal_arns=$admins" "${nodes[@]}"

aws eks update-kubeconfig --region "$AWS_REGION" --name "$(tf_out "$TF_EKS" cluster_name)" --alias "$EKS_CTX" >/dev/null
kubectl --context "$EKS_CTX" wait --for=condition=Ready nodes --all --timeout=10m

install_argocd "$EKS_CTX"
apply_root_app "$EKS_CTX" eks
wait_for_apps "$EKS_CTX" 1800 || warn "Still syncing; check with: bash scripts/eks-status.sh"

cat <<INFO

EKS is up ($cost). Open the UIs through port-forwards (Ctrl+C to stop):
  kubectl --context $EKS_CTX -n argocd port-forward svc/argocd-server 8090:80
  kubectl --context $EKS_CTX -n monitoring port-forward svc/kps-grafana 3000:80
  kubectl --context $EKS_CTX -n demo port-forward svc/demo-app 8081:80
Chaos scripts work too:  KUBE_CONTEXT=$EKS_CTX bash chaos/error-spike.sh

Stop:  bash scripts/eks-down.sh
INFO
