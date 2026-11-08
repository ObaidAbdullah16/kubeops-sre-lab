#!/usr/bin/env bash
# Shared helpers for the chaos scripts. Sourced, not executed.
set -euo pipefail
CTX="${KUBE_CONTEXT:-$(kubectl config current-context)}"
k() { kubectl --context "$CTX" "$@"; }
log() { printf '\033[1;35m[chaos %s]\033[0m %s\n' "$(date +%H:%M:%S)" "$*"; }

# set_chaos key=value ... : merge settings into the demo-chaos ConfigMap.
# Pods re-read it within ~60-90 s (kubelet volume sync + 5 s app reload).
set_chaos() {
  local current args=()
  current="$(k -n demo get configmap demo-chaos -o json 2>/dev/null || echo '{"data":{}}')"
  declare -A kv=()
  while IFS='=' read -r key val; do
    [[ -n "$key" ]] && kv[$key]="$val"
  done < <(python3 -c 'import json,sys; [print(f"{k}={v}") for k,v in (json.load(sys.stdin).get("data") or {}).items()]' <<<"$current")
  for pair in "$@"; do kv[${pair%%=*}]="${pair#*=}"; done
  for key in "${!kv[@]}"; do args+=("--from-literal=$key=${kv[$key]}"); done
  k -n demo create configmap demo-chaos "${args[@]}" --dry-run=client -o yaml | k apply -f - >/dev/null
  log "demo-chaos is now: $(k -n demo get configmap demo-chaos -o jsonpath='{.data}')"
}
