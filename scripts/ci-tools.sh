#!/usr/bin/env bash
# Install the validation CLIs used by CI (and handy locally) into ./.bin:
# kubeconform, kyverno CLI and promtool - pinned versions, checksums verified.
#   bash scripts/ci-tools.sh && export PATH="$PWD/.bin:$PATH"
set -euo pipefail
KUBECONFORM_VERSION="v0.8.0"
KYVERNO_VERSION="v1.19.1"     # same as the Kyverno chart 3.9.1 in gitops/root/values.yaml
PROMETHEUS_VERSION="3.15.0"   # same as kube-prometheus-stack 92.7.0

bin="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.bin"
mkdir -p "$bin"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
case "$(uname -m)" in
  x86_64) arch=amd64; karch=x86_64 ;;
  aarch64|arm64) arch=arm64; karch=arm64 ;;
  *) echo "unsupported CPU $(uname -m)" >&2; exit 1 ;;
esac

fetch() { curl -fsSL --retry 3 -o "$2" "$1"; }
verify() { # verify <checksum file> <pattern> <file>
  local sum; sum="$(grep -E "$2" "$1" | head -1 | awk '{print $1}')"
  [[ -n "$sum" ]] || { echo "no checksum for $2" >&2; exit 1; }
  echo "$sum  $3" | sha256sum -c - >/dev/null
}

if ! "$bin/kubeconform" -v 2>/dev/null | grep -q "$KUBECONFORM_VERSION"; then
  base="https://github.com/yannh/kubeconform/releases/download/$KUBECONFORM_VERSION"
  fetch "$base/kubeconform-linux-$arch.tar.gz" "$tmp/kc.tgz"
  fetch "$base/CHECKSUMS" "$tmp/kc.sums"
  verify "$tmp/kc.sums" "kubeconform-linux-$arch.tar.gz" "$tmp/kc.tgz"
  tar -xzf "$tmp/kc.tgz" -C "$bin" kubeconform
fi

if ! "$bin/kyverno" version 2>/dev/null | grep -q "${KYVERNO_VERSION#v}"; then
  base="https://github.com/kyverno/kyverno/releases/download/$KYVERNO_VERSION"
  fetch "$base/kyverno-cli_${KYVERNO_VERSION}_linux_${karch}.tar.gz" "$tmp/kyv.tgz"
  fetch "$base/checksums.txt" "$tmp/kyv.sums"
  verify "$tmp/kyv.sums" "kyverno-cli_${KYVERNO_VERSION}_linux_${karch}.tar.gz" "$tmp/kyv.tgz"
  tar -xzf "$tmp/kyv.tgz" -C "$bin" kyverno
fi

if ! "$bin/promtool" --version 2>/dev/null | grep -q "$PROMETHEUS_VERSION"; then
  base="https://github.com/prometheus/prometheus/releases/download/v$PROMETHEUS_VERSION"
  name="prometheus-$PROMETHEUS_VERSION.linux-$arch"
  fetch "$base/$name.tar.gz" "$tmp/prom.tgz"
  fetch "$base/sha256sums.txt" "$tmp/prom.sums"
  verify "$tmp/prom.sums" "$name.tar.gz" "$tmp/prom.tgz"
  tar -xzf "$tmp/prom.tgz" -C "$tmp" "$name/promtool"
  mv "$tmp/$name/promtool" "$bin/"
fi
echo "tools ready in $bin"
