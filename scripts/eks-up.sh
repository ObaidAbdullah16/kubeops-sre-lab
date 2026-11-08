#!/usr/bin/env bash
# Optional demo day on AWS: create an EKS cluster (2 Graviton nodes: spot, or on-demand in a
# project account from the new AWS sign-up, which cannot use spot) and deploy the same GitOps
# stack as the kind lab. ~20 minutes. ~$0.15/hour with spot, ~$0.20/hour on-demand.
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
if [[ "${AWS_ACCOUNT_TYPE:-classic}" == project ]]; then
  nodes=(-var "capacity_type=ON_DEMAND" -var 'node_instance_types=["t4g.medium"]')
  cost="~\$0.20/hour"
fi
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
