#!/usr/bin/env bash
# GD-04: try to ship things the platform must refuse. Each attempt is a server-side
# dry run, so nothing is created even if a policy were missing.
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
here="$(dirname "${BASH_SOURCE[0]}")"
try() {
  local name="$1" file="$2"
  printf '\n\033[1m%s\033[0m\n' "$name"
  if out="$(k apply --dry-run=server -f "$file" 2>&1)"; then
    printf '  \033[1;31mACCEPTED (policy gap!)\033[0m %s\n' "$out"
  else
    printf '  \033[1;32mREJECTED\033[0m %s\n' "$(grep -oE '(denied the request|message).*' <<<"$out" | head -3)"
  fi
}
try "1. nginx:latest from Docker Hub, as root, no probes or limits" "$here/manifests/insecure.yaml"
try "2. Our own image by tag (not digest) - cannot be signature-verified" "$here/manifests/unsigned-tag.yaml"
try "3. Our own image by a digest that CI never signed" "$here/manifests/unsigned-digest.yaml"
