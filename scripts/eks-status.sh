#!/usr/bin/env bash
# Is the optional EKS cluster running (and costing money)?
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=tf.sh
source "$(dirname "${BASH_SOURCE[0]}")/tf.sh"
need aws terraform
tf_init "$TF_EKS" "kubeops-sre-lab/eks.tfstate"
if ! tf_has_resources "$TF_EKS"; then
  echo "kubeops-eks: DOWN (costs nothing)"
  exit 0
fi
name="$(tf_out "$TF_EKS" cluster_name)"
echo "kubeops-eks: UP (~\$0.15-0.35/hour - stop with: bash scripts/eks-down.sh)"
aws eks describe-cluster --name "$name" --query 'cluster.{status:status,version:version,endpoint:endpoint}' --output table
aws eks list-nodegroups --cluster-name "$name" --output text
if command -v kubectl >/dev/null && kubectl --context "$EKS_CTX" get nodes >/dev/null 2>&1; then
  kubectl --context "$EKS_CTX" get nodes
  kubectl --context "$EKS_CTX" -n argocd get applications.argoproj.io 2>/dev/null || true
fi
