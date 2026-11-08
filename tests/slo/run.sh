#!/usr/bin/env bash
# Unit-test the SLO recording rules and burn-rate alerts with promtool.
# Extracts the rule groups from the PrometheusRule manifest first.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$here/../.."
python3 - "$root/gitops/observability/slo-rules.yaml" "$here/rules.generated.yaml" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
yaml.safe_dump({"groups": doc["spec"]["groups"]}, open(sys.argv[2], "w"), sort_keys=False)
PY
promtool check rules "$here/rules.generated.yaml"
promtool test rules "$here/slo-test.yaml"
