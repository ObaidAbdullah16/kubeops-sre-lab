# Postmortem: slow order requests from a degraded dependency (game day GD-02)

| | |
|---|---|
| Date | Example game day |
| Duration | 14:20 → 14:55 UTC, 35 minutes |
| Severity | SEV-3 (degraded, no errors) |
| Status | Reviewed |

## Summary
About 30% of `/api/*` requests took ~400 ms longer than usual for 35 minutes. No
request failed, so the availability SLO was untouched, but the latency SLO (99% under
300 ms) was badly violated. The latency burn-rate alert paged after 31 minutes.

## Impact
* ~6,300 of ~21,000 requests slower than 300 ms (≈30%; objective ≤ 1%).
* p50 unchanged (≈2 ms) - **p95 rose to ~405 ms**. An average-latency graph would have
  shown ~120 ms and looked "fine".

## Timeline (UTC)
| Time | Event |
|---|---|
| 14:20 | Latency injected (`latency_ms=400`, `latency_rate=0.3`) |
| 14:22 | p95/p99 panels jump; p50 flat |
| 14:51 | `DemoLatencyBudgetBurnFast` fired: the 1-hour slow ratio crossed 14.4% |
| 14:52 | All three pods equally slow (Loki: `duration_ms > 300` grouped by pod) → shared cause, not a node |
| 14:53 | Setting rolled back with `chaos/reset.sh` |
| 14:55 | p95 back under 10 ms; alert resolved 14:57 |

## Root cause
A shared dependency (simulated by the chaos setting) added 400 ms to a third of the
calls. The service has no timeout or fallback for it.

## Detection
Good: the alert was based on the share of slow requests, not the average, and the
5-minute confirmation window made it resolve quickly after the fix. Slow: it paged 31
minutes after the p95 panel showed the problem, the same detection trade-off as GD-01.

## Action items
| Action | Type | Owner | Due |
|---|---|---|---|
| Add a client timeout (250 ms) + one retry with jitter for the dependency | mitigate | Obaid | +1 week |
| Add per-dependency latency metrics so the slow component is visible directly | detect | Obaid | +2 weeks |
| Load-test retries to avoid retry storms (amplification) | prevent | Obaid | +3 weeks |
