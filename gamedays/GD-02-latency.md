# GD-02 - Latency regression

**Story:** a downstream dependency became slow. Requests still succeed, but 30% take
~400 ms longer.

## Run it

```bash
bash chaos/latency.sh 400 0.3
```

## Expected signals

* *Latency percentiles*: p50 barely moves, **p95/p99 jump above 300 ms** - averages hide this.
* *Slow requests vs objective*: ~30% (objective 1%).
* `DemoLatencyBudgetBurnFast` fires after ~30 minutes, when the 1-hour slow ratio crosses 14.4% (sooner
  on a lab started less than an hour ago). No availability alert fires.

## Respond

1. Confirm user impact on the SLO dashboard (which percentile, which route).
2. Find the cause: Loki `{namespace="demo"} | json | duration_ms > 300` - all pods? one pod?
   (all → shared dependency/config; one → node or pod problem).
3. Mitigate: `bash chaos/reset.sh` (in real life: roll back, raise timeouts carefully, shed load).
4. Verify p95 < 300 ms and the alert resolves.

## Discussion points

* Why measure "share of requests under 300 ms" instead of "average latency"?
* What would a timeout + retry do here (retry storms, amplification)?
