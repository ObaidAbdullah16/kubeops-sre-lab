#!/usr/bin/env bash
# GD-02: add latency to a share of API requests (default 400 ms on 30%).
#   bash chaos/latency.sh [ms] [share]
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
set_chaos "latency_ms=${1:-400}" "latency_rate=${2:-0.3}"
log "Expect: p95 > 300 ms within ~2 min. DemoLatencyBudgetBurnFast pages when the 1h slow ratio reaches"
log "14.4%: ~30 min at a 0.3 share (sooner on a lab started < 1 h ago, or with a larger share)."
