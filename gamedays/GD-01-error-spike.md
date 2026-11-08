# GD-01 - Error spike after a configuration change

**Story:** a teammate pushed a configuration change; some requests to the orders
API now fail with HTTP 500. Nobody has noticed yet.

## Run it

```bash
bash chaos/error-spike.sh 0.15     # 15% of /api requests return 500
```

## Expected signals (timeline)

| Time | Signal |
|---|---|
| +1-2 min | *Error ratio* panel rises to ~15%; *Availability (1h)* starts falling below 99.5% |
| +2 min | Loki shows `"status":500` lines with `injected failure (chaos error_rate)` |
| +5 min | *Error ratio vs burn-rate thresholds*: the 5-minute ratio is far above the 14.4x line; the 1-hour ratio climbs ~0.25 percentage points per minute |
| **+~30 min** | `DemoErrorBudgetBurnFast` (critical) firing: the 1-hour error ratio crossed 7.2% (14.4x). On a lab started less than an hour ago it fires after ~10 min, because the long windows only hold data since start |
| later | `DemoErrorBudgetBurnSlow` condition true too, but **inhibited** by the critical alert |

> **Note:** the page comes ~30 minutes after the dashboard shows the problem, and that is by design:
> a 15% error rate is allowed to use about 2% of the monthly budget before anyone is woken up. A full
> outage pages in ~6 minutes. `tests/slo/slo-test.yaml` pins this timing. For a shorter recording,
> run `bash chaos/error-spike.sh 0.5` (pages after ~10 minutes).

## Respond

1. **Acknowledge** and start the timeline (scribe).
2. **Impact**: how many requests fail? Since when? (*Requests per second by status code*.)
3. **What changed?** Argo CD history shows no new deploy. Check config outside Git:
   `kubectl -n demo get configmap demo-chaos -o yaml` → `error_rate: "0.15"`.
4. **Mitigate first, investigate later**: roll the config back - `bash chaos/reset.sh`.
5. **Verify**: error ratio back to ~0 within ~2 min, alert resolves.
6. **Budget**: note the *Monthly budget used* stat - this incident's cost in SLO terms.

## Discussion points

* Why does `/healthz` keep returning 200? (Liveness ≠ correctness - restarts would not help.)
* Why two windows (1h and 5m)? Long window = significance, short window = "still happening" → fast reset after the fix.
* Is a 30-minute page acceptable for 15% failed checkouts? If not: a faster pair (e.g. 30m and 3m at 14.4x pages in ~16 min) at the cost of more noise, or a tighter SLO.
* Prevention: config changes through Git + review (the lab keeps chaos outside Git on purpose).
