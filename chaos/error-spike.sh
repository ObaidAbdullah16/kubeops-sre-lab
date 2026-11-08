#!/usr/bin/env bash
# GD-01: make a share of API requests fail (default 15%) - like a bad config push.
#   bash chaos/error-spike.sh [rate]       e.g. 0.15
# Undo: bash chaos/reset.sh
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
rate="${1:-0.15}"
set_chaos "error_rate=$rate"
log "Expect: error ratio panel rises in ~1-2 min. DemoErrorBudgetBurnFast pages when the 1h error ratio"
log "reaches 7.2%: ~30 min at 0.15, ~10 min at 0.5, ~6 min at 1.0 (sooner on a lab started < 1 h ago)."
