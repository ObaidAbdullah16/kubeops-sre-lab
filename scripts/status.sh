#!/usr/bin/env bash
# Show the state of the local lab.
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need kind kubectl
if ! kind_cluster_exists; then
  echo "kubeops (kind): DOWN (start: bash scripts/up.sh)"
  exit 0
fi
if kind_cluster_paused; then
  echo "kubeops (kind): PAUSED - uses no memory; 'bash scripts/up.sh' resumes it in ~2-3 minutes ('down --all' deletes it)"
  exit 0
fi
echo "kubeops (kind): UP - free, on your laptop (stop: bash scripts/down.sh)"
echo "== Nodes"
kubectl --context "$KCTX" get nodes -o wide | awk '{print $1, $2, $5}' | column -t
echo
echo "== Argo CD applications"
kubectl --context "$KCTX" -n argocd get applications.argoproj.io \
  -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,REVISION:.status.sync.revision 2>/dev/null || true
echo
echo "== Demo namespace"
kubectl --context "$KCTX" -n demo get pods -o wide 2>/dev/null | awk '{print $1, $2, $3, $4, $7}' | column -t || true
echo
echo "== Chaos settings"
kubectl --context "$KCTX" -n demo get configmap demo-chaos -o jsonpath='{.data}' 2>/dev/null || echo "none (healthy)"
echo
echo
echo "== Firing alerts"
curl -fsS -m 5 http://localhost:9093/api/v2/alerts?active=true 2>/dev/null \
  | python3 -c 'import json,sys; [print(" ", a["labels"]["alertname"], a["labels"].get("severity","")) for a in json.load(sys.stdin)]' \
  || echo "  (Alertmanager not reachable)"
