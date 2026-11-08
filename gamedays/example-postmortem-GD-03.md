# Postmortem: worker node crash reduced capacity for 5 minutes (game day GD-03)

| | |
|---|---|
| Date | Example game day |
| Duration | 09:05 → 09:12 UTC, 7 minutes (reduced redundancy, no user impact) |
| Severity | SEV-3 |
| Status | Reviewed |

## Summary
Worker node `kubeops-worker` stopped (simulated crash). One of three demo-app replicas
was on it. Requests kept succeeding through the remaining two replicas; the third was
recreated on the other worker only after the node's pods were evicted ~5 minutes later.

## Impact
* No failed user requests (error ratio stayed 0%).
* For ~5 minutes the service ran with 2 replicas: one more failure would have caused an outage.

## Timeline (UTC)
| Time | Event |
|---|---|
| 09:05 | Node container stopped |
| 09:06 | Node `NotReady` (~40 s); Prometheus stops scraping the pod on it |
| 09:08 | `DemoReplicasDown` **did not** fire - 2 of 3 replicas still up (threshold is < 2) |
| 09:10 | Pods on the dead node marked for eviction (default `tolerationSeconds: 300`) |
| 09:11 | Replacement pod Running and Ready on `kubeops-worker2` |
| 09:12 | Node restarted; scheduler later rebalances only for new pods |

## Root cause
Simulated node failure. The slow recovery is the Kubernetes default: pods tolerate
`node.kubernetes.io/unreachable` for 300 s before eviction.

## What went well / badly
* Well: topology spread kept replicas on different nodes, so one node cost one replica.
* Badly: 5 minutes with no spare capacity, and no alert told us redundancy was reduced.
* Note: the PodDisruptionBudget did not help here - PDBs only cover *voluntary* disruptions.

## Action items
| Action | Type | Owner | Due |
|---|---|---|---|
| Set `tolerationSeconds: 60` for unreachable/not-ready on demo-app | mitigate | Obaid | +1 week |
| Add a warning alert when ready replicas < desired for 2 minutes | detect | Obaid | +1 week |
| Run 4 replicas across 3 nodes in production-like setups | prevent | Obaid | backlog |
