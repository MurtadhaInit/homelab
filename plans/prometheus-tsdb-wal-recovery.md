# Prometheus TSDB Recovery: Clearing the Corrupt WAL

Prometheus is running again after the 2026-08-18 disk-full incident, but its
compaction is permanently broken by a WAL segment that was truncated mid-write
when the volume filled. Until the WAL is cleared, the database can never
checkpoint, never truncate, and will slowly grow back into the same wall.

## Root Cause

The incident had three distinct layers, and only the first is the obvious one.

**1. Size retention could never act.** `--storage.tsdb.retention.size` counts the
WAL and m-mapped head chunks toward its total, but **only persisted blocks are
deleted to honour it**. This instance reports `prometheus_tsdb_blocks_loaded: 0`
— it has never successfully compacted anything, so there were no blocks to
delete and size retention had nothing to act on. The WAL grew unbounded until it
filled the 8Gi volume. `retentionSize: 6GiB` on an 8Gi volume left almost no
headroom for the head (which peaks every 2h) plus compaction scratch, so this was
always going to be tight even had compaction worked.

**2. The failure was self-sealing.** Retention and compaction only run *after* a
successful startup, and startup has to write during WAL replay. Once the disk was
full, Prometheus died during replay — before ever reaching the code that would
have freed space. Each restart appended more WAL. It crashlooped for seven days
and ~2000 restarts.

**3. The startup probe made recovery impossible on its own.** The probe polls
`/-/ready`, which returns 503 for the entire WAL replay, with a default budget of
`60 × 15s = 900s`. With ~2900 WAL segments the replay needed far longer than 15
minutes, so even on a bigger disk the kubelet would kill the container mid-replay
and restart it from zero, forever. **A larger volume alone would not have fixed
this** — `maximumStartupDurationSeconds` was the load-bearing change.

**The residue.** The original `ENOSPC` left WAL segment `00002010` truncated
mid-record. Replay tolerates it (it starts at 2011, and
`prometheus_tsdb_wal_corruptions_total` is 0), but checkpoint creation reads
straight through it and dies:

```
compaction failed: WAL truncation in Compact: create checkpoint: read segments:
corruption in segment /prometheus/wal/00002010 at 408: unexpected full record
```

`Compact()` → `truncateWAL()` → `Checkpoint()` fails on every attempt, so the WAL
is never truncated. `prometheus_tsdb_compactions_failed_total` has gone 1 → 22
over two days: this is not self-healing.

## Current State

```
prometheus-kube-prometheus-stack-prometheus-0  @ talos-worker-1   Ready, scraping 40 targets
├── PVC  prometheus-…-prometheus-0             20Gi (grown from 8Gi, online)
│     mounted at /prometheus  with  subPath: prometheus-db      ← note the subPath
├── blocks_loaded              0        ← never compacted, no persisted blocks
├── compactions_failed_total  22        ← climbing, one per attempt
├── wal_segment_current     2149        ← still growing
├── head_series          111,284
└── head window          ~1h of live data only (older samples already GC'd)

live overrides not yet in git (applied by hand during recovery):
  maximumStartupDurationSeconds: 7200    ← in the manifest, awaiting push
  PVC size 20Gi                          ← manifest says 20Gi, awaiting push
  running container still has --storage.tsdb.retention.size=6GiB
```

**The data at risk is worth about an hour.** `blocks_loaded` is 0, so no
historical blocks exist, and the head only spans the last hour — everything older
was already outside the 7d retention window and has been garbage-collected out of
memory. Wiping the TSDB costs an hour of metrics and nothing else.

## Plan

### Prerequisite: land the manifest change first

The `kube-prometheus-stack.yaml` changes (20Gi volume, `retentionSize: 14GiB`,
`maximumStartupDurationSeconds: 7200`) must be committed, pushed, and reconciled
**before** the recovery. Otherwise a recreated PVC comes back at the template's
old 8Gi and the whole exercise repeats. Confirm with:

```nu
kubectl -n monitoring get prometheus kube-prometheus-stack-prometheus -o yaml | find -r "storage:|maximumStartup|retentionSize"
```

### Option A (preferred): recreate the PVC

Simplest and most robust — no filesystem surgery, and the new volume is created
straight from the corrected template.

```nu
# 1. scale down via the CR (the operator reverts a direct `kubectl scale` on the STS)
kubectl -n monitoring patch prometheus kube-prometheus-stack-prometheus --type=merge -p '{"spec":{"replicas":0}}'
kubectl -n monitoring wait --for=delete pod/prometheus-kube-prometheus-stack-prometheus-0 --timeout=120s

# 2. drop the volume
kubectl -n monitoring delete pvc prometheus-kube-prometheus-stack-prometheus-db-prometheus-kube-prometheus-stack-prometheus-0

# 3. back up
kubectl -n monitoring patch prometheus kube-prometheus-stack-prometheus --type=merge -p '{"spec":{"replicas":1}}'
```

The operator recreates the PVC from the (now 20Gi) template, Longhorn provisions
a fresh 2-replica volume, and Prometheus starts on an empty TSDB — replay is
instant, compaction works from the first 2h block onward.

Afterwards, revert the `replicas` override so the CR matches the chart values
again, or it will drift on the next Helm upgrade.

### Option B (fallback): wipe the WAL in place

Use this only if the ~1h of head data is worth preserving *and* the head has been
flushed to a block first. Note the `subPath` — the data is **not** at the root of
the PVC:

```yaml
# tsdb-repair.yaml — throwaway pod, delete when done
apiVersion: v1
kind: Pod
metadata:
  name: tsdb-repair
  namespace: monitoring
spec:
  restartPolicy: Never
  containers:
    - name: shell
      image: busybox:1.37
      command: ["sleep", "1800"]
      volumeMounts:
        - name: db
          mountPath: /data
  volumes:
    - name: db
      persistentVolumeClaim:
        claimName: prometheus-kube-prometheus-stack-prometheus-db-prometheus-kube-prometheus-stack-prometheus-0
```

```nu
# scale down first — the PVC is ReadWriteOnce
kubectl -n monitoring patch prometheus kube-prometheus-stack-prometheus --type=merge -p '{"spec":{"replicas":0}}'
kubectl apply -f tsdb-repair.yaml
kubectl -n monitoring exec tsdb-repair -- ls /data/prometheus-db          # sanity-check the subPath
kubectl -n monitoring exec tsdb-repair -- rm -rf /data/prometheus-db/wal /data/prometheus-db/chunks_head
kubectl -n monitoring delete pod tsdb-repair
kubectl -n monitoring patch prometheus kube-prometheus-stack-prometheus --type=merge -p '{"spec":{"replicas":1}}'
```

A more surgical variant — deleting only segments `<= 00002010` — was considered
and rejected: it keeps data that is already outside retention, and it risks
leaving the checkpoint reader in a worse state than a clean directory.

## Prevention

The durable lesson is that this failed silently for seven days. Losing metrics is
tolerable; not knowing the metrics stack is down is not — and Prometheus cannot
alert on its own death. Add to `k8s/infrastructure/configs/`:

```yaml
- alert: PrometheusCompactionFailing
  expr: increase(prometheus_tsdb_compactions_failed_total[3h]) > 0
  for: 30m
  labels: { severity: warning }
  annotations:
    summary: "Prometheus TSDB compaction is failing"
    description: "Compaction has failed in the last 3h. The WAL cannot be truncated and will grow until the volume fills."

- alert: PrometheusNoPersistedBlocks
  # blocks_loaded staying at 0 well past the 2h block boundary means compaction
  # has never succeeded — the exact shape of the 2026-08-18 incident.
  expr: prometheus_tsdb_blocks_loaded == 0
  for: 6h
  labels: { severity: warning }

- alert: PrometheusVolumeFillingUp
  expr: |
    kubelet_volume_stats_available_bytes{persistentvolumeclaim=~"prometheus-.*"}
      / kubelet_volume_stats_capacity_bytes{persistentvolumeclaim=~"prometheus-.*"} < 0.25
  for: 30m
  labels: { severity: warning }
```

The third one is the true safety net and it has a chicken-and-egg problem: a dead
Prometheus evaluates no rules. A `DeadMansSwitch` / `Watchdog` alert routed to an
external heartbeat service (Healthchecks.io, Uptime Kuma — already running here)
is what actually catches "the whole stack is down". kube-prometheus-stack ships a
`Watchdog` alert that always fires for exactly this purpose; wiring it to
Uptime Kuma is small and worth doing.

## Order of Operations

1. Commit and push the `kube-prometheus-stack.yaml` changes; wait for Flux.
2. Verify the Prometheus CR shows 20Gi / 14GiB / 7200s.
3. Run Option A.
4. Confirm recovery (below).
5. Add the alerting rules as a follow-up commit.
6. Wire `Watchdog` to Uptime Kuma — separate, and arguably the highest-value item
   here.

## Verification

```nu
# a block should appear within ~2-3h of a clean start, and stay non-zero
kubectl -n monitoring port-forward pod/prometheus-kube-prometheus-stack-prometheus-0 19090:9090
http get http://127.0.0.1:19090/api/v1/query?query=prometheus_tsdb_blocks_loaded
http get http://127.0.0.1:19090/api/v1/query?query=prometheus_tsdb_compactions_failed_total   # must stay flat
http get http://127.0.0.1:19090/api/v1/query?query=prometheus_tsdb_wal_segment_current        # must reset low and stay bounded
```

Watch `wal_segment_current` over a day: on a healthy instance it climbs and then
drops back as checkpoints truncate it. A monotonic climb means the problem is
back.

## Open Questions / Verifications Needed

- **Does `retention: 7d` plus `retentionSize: 14GiB` on a 20Gi volume actually
  hold?** With ~111k head series the steady-state footprint is unknown, because
  this instance has never produced a block to measure. Re-check the volume's
  usage after a week of healthy operation and tune from real numbers rather than
  the current guess.
- Whether 111k active series is itself reasonable for this cluster, or whether
  something (kubelet cAdvisor cardinality is the usual culprit) should be dropped
  at scrape time. That would shrink every downstream problem here.
- Whether to set `spec.replicas` back via the chart values rather than a direct
  CR patch, to avoid the drift noted in Option A.
