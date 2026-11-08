#!/usr/bin/env bash
# Stop the lab: delete the kind cluster (all data in it is thrown away).
#
#   bash scripts/down.sh          # deletes the cluster; keeps the cached kind node image (~1 GB)
#                                 # so the next 'up' starts faster
#   bash scripts/down.sh --all    # also deletes that image (frees the disk space)
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need kind docker

ALL=0
for a in "$@"; do
  case "$a" in
    --all) ALL=1 ;;
    *) die "unknown option: $a (use --all or nothing)" ;;
  esac
done

if kind_cluster_exists; then
  log "Deleting kind cluster '$CLUSTER'"
  kind delete cluster --name "$CLUSTER"
else
  log "No kind cluster named '$CLUSTER'"
fi
if [[ "$ALL" == 1 ]]; then
  for img in $(docker images --format '{{.Repository}}:{{.Tag}}' | grep '^kindest/node:' || true); do
    docker rmi "$img" >/dev/null && log "Deleted image $img"
  done
fi
log "Down. Docker memory is free again."
