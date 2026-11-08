#!/usr/bin/env bash
# Stop the lab.
#
#   bash scripts/down.sh          # pauses it: stops the three node containers, so Docker's memory
#                                 # is free again, but keeps the cluster and the ~2 GB of images
#                                 # inside it. The next 'up' resumes it in about 2-3 minutes.
#   bash scripts/down.sh --all    # deletes the cluster and the cached kind node image (frees the
#                                 # disk space; the next 'up' downloads everything again: 15-25 minutes)
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

if ! kind_cluster_exists; then
  log "No kind cluster named '$CLUSTER'"
elif [[ "$ALL" == 1 ]]; then
  log "Deleting kind cluster '$CLUSTER'"
  kind delete cluster --name "$CLUSTER"
else
  log "Pausing kind cluster '$CLUSTER' (the next 'up' resumes it; 'down --all' deletes it)"
  # shellcheck disable=SC2046  # one argument per node container
  docker stop $(kind_nodes) >/dev/null
fi
if [[ "$ALL" == 1 ]]; then
  for img in $(docker images --format '{{.Repository}}:{{.Tag}}' | grep '^kindest/node:' || true); do
    docker rmi "$img" >/dev/null && log "Deleted image $img"
  done
fi
log "Down. Docker memory is free again."
