#!/usr/bin/env bash
# Destroy the optional EKS cluster and everything in it (VPC, nodes, roles).
# Nothing is kept in AWS, so `eks-down.sh --all` does the same.
#   bash scripts/eks-down.sh      (or: bash scripts/eks-down.sh --all)
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=tf.sh
source "$(dirname "${BASH_SOURCE[0]}")/tf.sh"
for a in "$@"; do [[ "$a" == "--all" ]] || die "unknown option: $a (use --all or nothing)"; done
need aws terraform
tf_init "$TF_EKS" "kubeops-sre-lab/eks.tfstate"
if tf_has_resources "$TF_EKS"; then
  log "Terraform destroy (~10 minutes)"
  tf_destroy "$TF_EKS"
else
  log "EKS cluster is already down"
fi
kubectl config delete-context "$EKS_CTX" >/dev/null 2>&1 || true
log "Down. Nothing from the EKS demo is billing any more."
