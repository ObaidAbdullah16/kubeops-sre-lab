#!/usr/bin/env bash
# shellcheck disable=SC2034  # variables defined here are used by the scripts that source it
# Shared helpers for the lab scripts. Sourced, not executed.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$REPO_ROOT/../_setup/config.env" ]]; then
  # shellcheck disable=SC1091
  source "$REPO_ROOT/../_setup/config.env"
fi
: "${AWS_REGION:=ap-southeast-2}"
: "${AUTO_APPROVE:=1}"
export AWS_REGION AWS_DEFAULT_REGION="$AWS_REGION"
[[ -n "${AWS_PROFILE:-}" ]] && export AWS_PROFILE

CLUSTER="${CLUSTER:-kubeops}"
KCTX="kind-${CLUSTER}"
ARGOCD_CHART_VERSION="10.10.3" # Argo CD v3.5.5

log()  { printf '\033[1;34m[%s]\033[0m %s\n' "$(date +%H:%M:%S)" "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

need() {
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "'$c' is not installed (see _setup/install-tools-wsl.sh)"
  done
}

# The Git repository Argo CD should deploy from: this clone's GitHub remote (so
# forks work), or the original repository.
repo_url() {
  local url
  url="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true)"
  case "$url" in
    git@github.com:*) url="https://github.com/${url#git@github.com:}" ;;
    https://github.com/*) ;;
    *) url="https://github.com/${GITHUB_OWNER:-ObaidAbdullah16}/kubeops-sre-lab.git" ;;
  esac
  [[ "$url" == *.git ]] || url="$url.git"
  echo "$url"
}

kind_cluster_exists() { kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; }

# install_argocd <kube context> : Helm install / upgrade of Argo CD
install_argocd() {
  local ctx="$1"
  helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
  helm repo update argo >/dev/null
  log "Installing Argo CD (chart $ARGOCD_CHART_VERSION)"
  helm upgrade --install argocd argo/argo-cd --kube-context "$ctx" \
    --namespace argocd --create-namespace --version "$ARGOCD_CHART_VERSION" \
    -f "$REPO_ROOT/bootstrap/argocd-values.yaml" --wait --timeout 10m >/dev/null
}

# apply_root_app <kube context> <profile: kind|eks> : the app of apps
apply_root_app() {
  local ctx="$1" profile="$2" url rev
  url="$(repo_url)"
  rev="${TARGET_REVISION:-main}"
  log "Root application -> $url ($rev, profile $profile)"
  kubectl --context "$ctx" apply -f - >/dev/null <<YAML
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root
  namespace: argocd
spec:
  project: default
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  source:
    repoURL: $url
    targetRevision: $rev
    path: gitops/root
    helm:
      parameters:
        - name: repoURL
          value: $url
        - name: targetRevision
          value: $rev
        - name: profile
          value: $profile
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
YAML
}

# wait_for_apps <kube context> [timeout seconds]
wait_for_apps() {
  local ctx="$1" timeout="${2:-1200}" start=$SECONDS line
  log "Waiting for Argo CD to sync everything (first run pulls ~2 GB of images: 5-15 minutes)"
  while :; do
    line="$(kubectl --context "$ctx" -n argocd get applications.argoproj.io \
      -o jsonpath='{range .items[*]}{.metadata.name}={.status.sync.status}/{.status.health.status} {end}' 2>/dev/null || true)"
    if [[ -n "$line" && "$line" != *OutOfSync* && "$line" != *Progressing* && "$line" != *Missing* \
          && "$line" != *Degraded* && "$line" != *Unknown* && "$line" == *demo=* && "$line" != *"/ "* ]]; then
      log "All applications Synced/Healthy"
      return 0
    fi
    (( SECONDS - start < timeout )) || { warn "Not all applications are healthy yet: $line"; return 1; }
    printf '  %s\n' "$line"
    sleep 20
  done
}

demo_digest_is_placeholder() {
  grep -q 'sha256:0000000000000000000000000000000000000000000000000000000000000000' "$REPO_ROOT/gitops/apps/demo/kustomization.yaml"
}
