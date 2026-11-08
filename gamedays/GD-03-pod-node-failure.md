# GD-03 - Pod and node failures

Three short drills on Kubernetes self-healing.

## a) Kill pods

```bash
bash chaos/kill-pods.sh 1      # then try 2
```

Expected: the Deployment recreates pods within seconds; the readiness probe keeps
new pods out of the Service until they are ready; error ratio stays ~0. With 2 pods
killed at once capacity drops for a moment - is the SLO still fine?

## b) Node crash

```bash
bash chaos/node-failure.sh 180
```

Expected: node `NotReady` after ~40 s; its pods stay "Running" on the dead node
until the eviction timeout (5 min) - so for a few minutes you run on fewer
replicas. `DemoReplicasDown` fires if two replicas lived on that node (topology
spread makes that unlikely). Discuss: `tolerationSeconds`, why 3 replicas on 2
workers, PDB vs node crash (PDBs only protect against *voluntary* disruptions).

## c) Planned drain

```bash
bash chaos/drain-node.sh
```

Expected: the drain evicts pods one at a time; the PodDisruptionBudget
(`minAvailable: 2`) blocks evictions that would leave fewer than 2 ready replicas.

Finish with `bash chaos/reset.sh`.
