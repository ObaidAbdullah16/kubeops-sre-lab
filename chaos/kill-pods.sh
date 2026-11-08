#!/usr/bin/env bash
# GD-03a: delete demo-app pods (default 1). The Deployment replaces them; with
# readiness probes and 3 replicas, users should see no errors.
#   bash chaos/kill-pods.sh [count]
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
n="${1:-1}"
mapfile -t pods < <(k -n demo get pods -l app.kubernetes.io/name=demo-app -o name | shuf | head -n "$n")
for p in "${pods[@]}"; do
  log "Deleting $p"
  k -n demo delete "$p" --wait=false
done
k -n demo get pods -l app.kubernetes.io/name=demo-app -w --request-timeout=60s || true
