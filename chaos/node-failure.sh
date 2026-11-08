#!/usr/bin/env bash
# GD-03b: crash a worker node (stop its container) for N seconds, then bring it back.
#   bash chaos/node-failure.sh [seconds]     default 180
# Kubernetes marks the node NotReady after ~40 s and evicts its pods after ~5 min
# (default tolerations), so a short outage shows how much capacity you lose meanwhile.
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
secs="${1:-180}"
node="${NODE:-kubeops-worker}"
log "Pods on $node before the crash:"
k get pods -A --field-selector "spec.nodeName=$node" -o wide | awk 'NR==1 || /demo/'
log "Stopping node container $node"
docker stop "$node" >/dev/null
trap 'log "Starting $node again"; docker start "$node" >/dev/null' EXIT
for ((i = 0; i < secs; i += 15)); do
  sleep 15
  log "t+$((i + 15))s  node: $(k get node "$node" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')  ready demo pods: $(k -n demo get deploy demo-app -o jsonpath='{.status.readyReplicas}')"
done
