#!/usr/bin/env bash
# Undo all chaos: remove the chaos settings, restart stopped nodes, uncordon nodes.
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
k -n demo delete configmap demo-chaos --ignore-not-found >/dev/null && log "Chaos settings removed (pods pick it up within ~90 s)"
for n in $(docker ps -a --filter "name=kubeops-worker" --filter "status=exited" --format '{{.Names}}' 2>/dev/null); do
  log "Starting stopped node $n"; docker start "$n" >/dev/null
done
for n in $(k get nodes -o jsonpath='{range .items[?(@.spec.unschedulable==true)]}{.metadata.name} {end}'); do
  log "Uncordoning $n"; k uncordon "$n" >/dev/null
done
k -n demo scale deploy/loadgen --replicas=1 >/dev/null 2>&1 || true
log "Reset done"
