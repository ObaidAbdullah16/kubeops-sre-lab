#!/usr/bin/env bash
# GD-03c: planned maintenance. Drain a worker: the PodDisruptionBudget keeps at
# least 2 demo-app replicas running while pods move. Then uncordon it.
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
node="${NODE:-kubeops-worker}"
log "Draining $node (respects PodDisruptionBudgets)"
k drain "$node" --ignore-daemonsets --delete-emptydir-data --timeout=180s
k -n demo get pods -o wide
log "Uncordoning $node"
k uncordon "$node"
