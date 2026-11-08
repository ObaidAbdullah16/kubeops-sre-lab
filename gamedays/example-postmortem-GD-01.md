# Postmortem: 15% of order requests failed after a configuration change (game day GD-01)

| | |
|---|---|
| Date | Example game day (the lab had been running for several hours) |
| Duration | 10:02 → 10:38 UTC, 36 minutes |
| Severity | SEV-2 (partial outage, no data loss) |
| Status | Reviewed |

## Summary
A configuration change made ~15% of `/api/orders` requests return HTTP 500 for
36 minutes. The SLO dashboard showed it within 2 minutes, but nobody was watching it;
the fast burn-rate alert paged 31 minutes after the change. Rolling the configuration
back restored service within 2 minutes of diagnosis.

## Impact
* ~3,200 of ~21,600 requests failed (15%).
* ~2.5% of the monthly error budget consumed (at 10 req/s the 30-day budget is ~130,000 failed requests).

## Timeline (UTC)
| Time | Event |
|---|---|
| 10:02 | `demo-chaos` ConfigMap changed (`error_rate=0.15`) outside Git |
| 10:04 | Error ratio visibly up on the SLO dashboard (nobody watching) |
| 10:33 | `DemoErrorBudgetBurnFast` fired: the 1-hour error ratio crossed 7.2% (14.4x burn) |
| 10:34 | Acknowledged; dashboards confirm all three pods affected equally |
| 10:35 | Loki: `injected failure (chaos error_rate)`; Argo CD shows no deploy → config suspected |
| 10:36 | ConfigMap removed (rollback) |
| 10:38 | Pods reloaded the setting; error ratio back to 0; alert resolved 10:40 |

## Root cause
A runtime configuration value was changed directly in the cluster. The value is not
managed by Git, so it bypassed review and Argo CD could not revert it.

## Detection
Paged after 31 minutes. That is how the 1h/5m pair is designed: at a 15% error rate
(30x burn) the 1-hour ratio needs about 29 minutes to reach 7.2%, and the alert then
waits its 2-minute `for`. A full outage would have paged in about 6 minutes. Health
checks stayed green - correct, restarts would not have helped.

## What went well / badly / lucky
* Well: once it paged, the alert was actionable and linked to this runbook; diagnosis and
  mitigation took 3 minutes.
* Badly: 29 minutes of visible errors before anyone looked. Detection was most of the incident.
* Lucky: the change affected all pods equally, which pointed quickly at config.

## Action items
| Action | Type | Owner | Due |
|---|---|---|---|
| Move runtime config into Git (Argo CD-managed ConfigMap) | prevent | Obaid | +1 week |
| Kyverno policy: deny edits to ConfigMaps in `demo` except by Argo CD | prevent | Obaid | +2 weeks |
| Decide whether checkout needs a faster page: add a 30m/3m pair at 14.4x (pages a 15% spike in ~16 min) and measure the extra noise | detect | Obaid | +2 weeks |
| Add a "config changed" annotation to the SLO dashboard | detect | Obaid | +2 weeks |
