# Game days

A game day is a planned, safe rehearsal of an incident: you break something on
purpose, then practise detecting, diagnosing, fixing and writing it up. Each
scenario below takes 20-30 minutes and ends with a short postmortem.

| # | Scenario | What it trains | Script |
|---|---|---|---|
| [GD-01](GD-01-error-spike.md) | 15% of requests fail after a "config change" | SLO burn-rate alerts, logs, config rollback | `chaos/error-spike.sh` |
| [GD-02](GD-02-latency.md) | A dependency gets slow | Latency SLO, percentiles vs averages | `chaos/latency.sh` |
| [GD-03](GD-03-pod-node-failure.md) | Pods and a node die | Self-healing, PDBs, capacity | `chaos/kill-pods.sh`, `chaos/node-failure.sh`, `chaos/drain-node.sh` |
| [GD-04](GD-04-policy-guardrails.md) | Someone ships an insecure / unsigned image | Admission control, supply-chain trust | `chaos/bad-deploy.sh` |

Always finish with `bash chaos/reset.sh`.

## Roles (even when you are alone, say them out loud in the video)

* **Incident commander** - decides, keeps the timeline, calls "resolved".
* **Operator** - looks at dashboards / logs and runs commands.
* **Scribe** - writes the timeline (UTC times) for the postmortem.

## Where to look

| Question | Tool |
|---|---|
| Are users affected? How much budget is left? | Grafana → KubeOps → *Orders API - SLO* |
| What is alerting? | http://localhost:9093 (Alertmanager) |
| What changed? | Argo CD (http://localhost:8090) → app history; `kubectl -n demo get configmap demo-chaos -o yaml` |
| Why is it failing? | Grafana → Explore → Loki: `{namespace="demo", app="demo-app"} \| json \| status >= 500` |
| Is it the platform? | Grafana → KubeOps → *Platform*; `kubectl get nodes`, `kubectl -n demo get events --sort-by=.lastTimestamp` |

Write the postmortem with [postmortem-template.md](postmortem-template.md).
Written examples: [GD-01 error spike](example-postmortem-GD-01.md),
[GD-02 latency](example-postmortem-GD-02.md), [GD-03 node crash](example-postmortem-GD-03.md).
