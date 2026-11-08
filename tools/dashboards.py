"""Generate the Grafana dashboards as ConfigMaps (picked up by the Grafana sidecar).

    python3 tools/dashboards.py   # rewrites gitops/observability/dashboards.yaml

Dashboards are code: edit this file, regenerate, commit - Argo CD rolls them out.
"""

from __future__ import annotations

import json
from pathlib import Path

PROM = {"type": "prometheus", "uid": "prometheus"}
LOKI = {"type": "loki", "uid": "loki"}
SEL = 'job="demo-app",route=~"/api/.*"'
_next_id = 0


def pid() -> int:
    global _next_id
    _next_id += 1
    return _next_id


def stat(title, expr, x, y, unit="percentunit", thresholds=None, decimals=2, w=6, desc=""):
    return {
        "id": pid(), "type": "stat", "title": title, "description": desc, "datasource": PROM,
        "gridPos": {"x": x, "y": y, "w": w, "h": 4},
        "targets": [{"refId": "A", "expr": expr, "datasource": PROM}],
        "fieldConfig": {"defaults": {"unit": unit, "decimals": decimals, "thresholds": {
            "mode": "absolute", "steps": thresholds or [{"color": "green", "value": None}]}}, "overrides": []},
        "options": {"reduceOptions": {"calcs": ["lastNotNull"]}, "colorMode": "background", "graphMode": "area"},
    }


def ts(title, targets, x, y, unit="short", w=12, h=8, desc="", source=PROM):
    return {
        "id": pid(), "type": "timeseries", "title": title, "description": desc, "datasource": source,
        "gridPos": {"x": x, "y": y, "w": w, "h": h},
        "targets": [{"refId": chr(65 + i), "expr": e, "legendFormat": legend, "datasource": source}
                    for i, (e, legend) in enumerate(targets)],
        "fieldConfig": {"defaults": {"unit": unit, "custom": {"lineWidth": 2, "fillOpacity": 10}}, "overrides": []},
        "options": {"legend": {"displayMode": "list", "placement": "bottom"}, "tooltip": {"mode": "multi"}},
    }


def logs(title, expr, x, y, w=24, h=10):
    return {
        "id": pid(), "type": "logs", "title": title, "datasource": LOKI,
        "gridPos": {"x": x, "y": y, "w": w, "h": h},
        "targets": [{"refId": "A", "expr": expr, "datasource": LOKI}],
        "options": {"showTime": True, "wrapLogMessage": True, "sortOrder": "Descending", "enableLogDetails": True},
    }


def dashboard(uid, title, panels, tags):
    return {
        "uid": uid, "title": title, "tags": tags, "timezone": "browser", "schemaVersion": 39,
        "refresh": "30s", "time": {"from": "now-1h", "to": "now"}, "editable": True,
        "panels": panels, "templating": {"list": []}, "annotations": {"list": []},
    }


def slo_dashboard():
    red_below = lambda v: [{"color": "red", "value": None}, {"color": "green", "value": v}]  # noqa: E731
    green_below = lambda v: [{"color": "green", "value": None}, {"color": "red", "value": v}]  # noqa: E731
    panels = [
        stat("Availability (last 1h)", "1 - demo:sli_errors:ratio_rate1h", 0, 0, thresholds=red_below(0.995),
             desc="Share of /api requests that did not return 5xx. SLO: 99.5%."),
        stat("Error budget burn rate (1h)", "demo:sli_errors:ratio_rate1h / 0.005", 6, 0, unit="none",
             thresholds=[{"color": "green", "value": None}, {"color": "orange", "value": 1}, {"color": "red", "value": 14.4}],
             desc="1 = spending the budget exactly as fast as it is earned. 14.4 = a 30-day budget gone in ~2 days (page)."),
        stat("Monthly budget used (last 7 days)", "demo:error_budget_consumed:ratio7d", 12, 0,
             thresholds=[{"color": "green", "value": None}, {"color": "orange", "value": 0.5}, {"color": "red", "value": 1}]),
        stat("p95 latency (5m)", f"histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket{{{SEL}}}[5m])))",
             18, 0, unit="s", thresholds=green_below(0.3), desc="Latency SLO: 99% of requests under 300 ms."),
        ts("Requests per second by status code", [(f"sum by (code) (rate(http_requests_total{{{SEL}}}[1m]))", "{{code}}")], 0, 4, unit="reqps"),
        ts("Error ratio vs burn-rate thresholds", [
            ("demo:sli_errors:ratio_rate5m", "5m"), ("demo:sli_errors:ratio_rate1h", "1h"),
            ("vector(14.4 * 0.005)", "page threshold (14.4x)"), ("vector(6 * 0.005)", "page threshold (6x)"),
            ("vector(0.005)", "SLO (0.5%)")], 12, 4, unit="percentunit"),
        ts("Latency percentiles", [
            (f"histogram_quantile({q}, sum by (le) (rate(http_request_duration_seconds_bucket{{{SEL}}}[5m])))", f"p{int(q * 100)}")
            for q in (0.5, 0.95, 0.99)], 0, 12, unit="s"),
        ts("Slow requests (> 300 ms) vs objective", [
            ("demo:sli_slow:ratio_rate5m", "5m"), ("demo:sli_slow:ratio_rate1h", "1h"), ("vector(0.01)", "SLO (1%)")],
            12, 12, unit="percentunit"),
        ts("Replicas scraped and chaos settings", [
            ('sum(up{job="demo-app"})', "replicas up"),
            ('max(demo_chaos_error_rate) * 100', "injected error rate (%)"),
            ('max(demo_chaos_latency_seconds) * 1000', "injected latency (ms)")], 0, 20, w=24, h=7,
            desc="Chaos values come from the demo-chaos ConfigMap (chaos/*.sh)."),
        logs("Errors from the orders API (Loki)",
             '{namespace="demo", app="demo-app"} | json | status >= 500', 0, 27),
    ]
    return dashboard("orders-slo", "Orders API - SLO", panels, ["kubeops", "slo"])


def platform_dashboard():
    panels = [
        ts("Pod restarts in demo (10m)", [('sum by (pod) (increase(kube_pod_container_status_restarts_total{namespace="demo"}[10m]))', "{{pod}}")], 0, 0),
        ts("Ready pods per deployment", [('sum by (deployment) (kube_deployment_status_replicas_ready{namespace="demo"})', "{{deployment}}")], 12, 0),
        ts("CPU by pod (cores)", [('sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="demo",container!=""}[2m]))', "{{pod}}")], 0, 8),
        ts("Memory working set by pod", [('sum by (pod) (container_memory_working_set_bytes{namespace="demo",container!=""})', "{{pod}}")], 12, 8, unit="bytes"),
        ts("Kyverno admission requests", [('sum by (resource_request_operation, allowed) (rate(kyverno_admission_requests_total[5m]))', "{{resource_request_operation}} allowed={{allowed}}")], 0, 16, unit="reqps"),
        ts("Log lines per second by namespace (Loki)", [('sum by (namespace) (rate({namespace=~".+"}[1m]))', "{{namespace}}")], 12, 16, source=LOKI),
        logs("All demo namespace logs", '{namespace="demo"}', 0, 24),
    ]
    return dashboard("kubeops-platform", "KubeOps - Platform", panels, ["kubeops"])


def configmap(name, dash):
    body = json.dumps(dash, indent=2)
    indented = "\n".join("    " + line for line in body.splitlines())
    return (
        "apiVersion: v1\nkind: ConfigMap\nmetadata:\n"
        f"  name: {name}\n  labels:\n    grafana_dashboard: \"1\"\n"
        "  annotations:\n    grafana_folder: KubeOps\n"
        f"data:\n  {name}.json: |\n{indented}\n"
    )


def main() -> None:
    out = Path(__file__).resolve().parent.parent / "gitops" / "observability" / "dashboards.yaml"
    header = "# Generated by tools/dashboards.py - edit that file, not this one.\n"
    out.write_text(header + configmap("dashboard-orders-slo", slo_dashboard()) + "---\n"
                   + configmap("dashboard-kubeops-platform", platform_dashboard()), encoding="utf-8")
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
