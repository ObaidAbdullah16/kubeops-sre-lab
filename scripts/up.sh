#!/usr/bin/env bash
# Start the lab on your laptop: kind cluster (3 nodes) + Argo CD, which then
# deploys Kyverno, Prometheus/Grafana/Alertmanager, Loki/Alloy, the policies,
# SLO rules, dashboards and the demo app from this Git repository.
# Needs Docker with ~6 GB of memory. Free. Stop with scripts/down.sh.
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need docker kind kubectl helm git

docker info >/dev/null 2>&1 || die "Docker is not running (start Docker Desktop)"
mem=$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo 0)
(( mem == 0 || mem >= 5500000000 )) || warn "Docker has only $((mem / 1024 / 1024 / 1024)) GB of memory; give it 6 GB+ (Docker Desktop > Settings > Resources)"

if demo_digest_is_placeholder; then
  warn "gitops/apps/demo/kustomization.yaml still has the placeholder image digest."
  warn "Push to main once so the Image workflow builds, signs and pins the demo image, then git pull."
  warn "Continuing: everything except the demo app will come up."
fi

if kind_cluster_exists && kind_cluster_paused; then
  log "Resuming the paused kind cluster '$CLUSTER'"
  # shellcheck disable=SC2046  # one argument per node container
  docker start $(kind_nodes) >/dev/null
  ready=0
  for _ in $(seq 1 36); do   # the API server needs ~30 s; give it up to 3 minutes
    if kubectl --context "$KCTX" wait --for=condition=Ready nodes --all --timeout=5s >/dev/null 2>&1; then
      ready=1; break
    fi
    sleep 5
  done
  if [[ "$ready" != 1 ]]; then
    warn "The paused cluster did not come back - creating it again (15-25 minutes)"
    kind delete cluster --name "$CLUSTER"
  fi
fi
if kind_cluster_exists; then
  log "kind cluster '$CLUSTER' already exists"
else
  log "Creating kind cluster '$CLUSTER' (1 control plane + 2 workers)"
  kind create cluster --config "$REPO_ROOT/kind/cluster.yaml" --name "$CLUSTER" --wait 120s
fi
kubectl config use-context "$KCTX" >/dev/null

install_argocd "$KCTX"
apply_root_app "$KCTX" kind
wait_for_apps "$KCTX" 1500 || warn "Run 'bash scripts/status.sh' in a few minutes; Argo CD keeps retrying."

pw="$(kubectl --context "$KCTX" -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || true)"
cat <<INFO

  Argo CD       http://localhost:8090   admin / ${pw:-<see argocd-initial-admin-secret>}
  Grafana       http://localhost:3000   admin / kubeops-lab   (Dashboards > KubeOps)
  Prometheus    http://localhost:9090
  Alertmanager  http://localhost:9093
  Demo API      http://localhost:8081/api/orders

  Game days:    see gamedays/README.md      Stop:  bash scripts/down.sh
INFO
