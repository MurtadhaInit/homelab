# Btrfs Scrub Monitoring & Alerting

End-to-end visibility into the monthly btrfs scrub on `/mnt/media`: a textfile-
collector wrapper that publishes scrub stats to Prometheus, alerts that catch
both silent service failures and bitrot/scrub-age regressions, and a small
Grafana panel set so the data is actually surfaced.

## Rationale

The monthly scrub configured in `ansible/playbooks/proxmox-fs.yaml` had been
silently failing on every fire (Apr 1, May 1) since deployment because the
`ExecStart` referenced `/usr/sbin/btrfs` — Debian 12 / PVE 8 use merged-`/usr`
and the binary is at `/usr/bin/btrfs`. No alerting existed, so the failures
went unnoticed for ~2 months. `btrfs scrub status /mnt/media` reports
"no stats available", confirming no scrub has ever completed against this
filesystem.

The fix to the path is a one-line change (already applied). The durable lesson
is that we need monitoring on this — not just for *this* failure mode, but
because btrfs scrub is the mechanism that detects bitrot on the media LV in the
first place. A silent scrub is worse than no scrub: it gives false confidence.

## Goals

1. Detect when the scrub service fails to run (covers the class of bug we
   just hit — wrong path, missing binary, mount disappeared, etc.).
2. Detect when the scrub *runs* but finds errors (uncorrectable / corrected /
   csum mismatches).
3. Detect when scrubs stop happening at all (timer broken, host down on
   schedule day, etc.) — i.e. last-successful-scrub age exceeds threshold.
4. Make the data visible in Grafana so a glance at the homelab dashboard tells
   me storage health is fine.

## Current State

```
proxmox host (10.20.30.40)
├── /mnt/media (btrfs, 350 GiB, zstd:noatime)
├── btrfs-scrub-media.{service,timer} — monthly, currently broken-then-fixed
├── node_exporter @ :9100
│     ├── systemd collector ENABLED → exposes per-unit state
│     ├── btrfs collector ENABLED (default) → device_errors_total etc.
│     └── textfile collector ENABLED → /var/lib/node_exporter (role default)
└── Prometheus ScrapeConfig (k8s/infrastructure/configs/proxmox-node-scrape.yaml)
        targets: 10.20.30.40:9100, label nodename=proxmox

k8s monitoring stack (kube-prometheus-stack)
├── Grafana — dashboards via configmap + sidecar (label grafana_dashboard=1)
├── node-exporter-full dashboard (Grafana 1860) already provisioned
└── Alertmanager — assumed wired to existing receiver(s)
```

## Plan

### 1. Fix the scrub `ExecStart` path — DONE

`ansible/playbooks/proxmox-fs.yaml:116` changed from `/usr/sbin/btrfs` to
`/usr/bin/btrfs`. Re-run the playbook; the `ansible.builtin.copy` rewrites the
unit and `ansible.builtin.systemd` with `daemon_reload: true` picks it up.

Verification:

```nu
just ansible-playbook proxmox-fs.yaml
ssh root@10.20.30.40 'systemctl start btrfs-scrub-media.service'
ssh root@10.20.30.40 'btrfs scrub status /mnt/media'  # should report real progress / completion
```

### 2. Post-scrub textfile collector script

Add a small shell wrapper that parses `btrfs scrub status -R` and atomically
writes Prometheus metrics. The textfile collector dir is the role default
(`/var/lib/node_exporter`); confirm with `systemctl cat node_exporter | grep textfile`
on the host before locking it in.

**Script** — written by Ansible to `/usr/local/sbin/btrfs-scrub-textfile.sh`:

```bash
#!/usr/bin/env bash
# Emits Prometheus textfile metrics describing the latest btrfs scrub on
# the given mountpoint. Reads on-disk scrub state via `btrfs scrub status -R`
# so it can run any time, not only immediately post-scrub.
set -euo pipefail

mount="${1:?mountpoint required}"
out_dir="${TEXTFILE_DIR:-/var/lib/node_exporter}"
out_file="${out_dir}/btrfs_scrub.prom"
tmp_file="$(mktemp "${out_file}.XXXXXX")"
trap 'rm -f "$tmp_file"' EXIT

status_raw="$(/usr/bin/btrfs scrub status -R "$mount" 2>/dev/null || true)"

# btrfs scrub status -R prints lines like '\tdata_bytes_scrubbed: 1234'.
# Helper: extract a numeric counter, default to 0 if absent (e.g. never run).
field() {
  awk -v k="$1" '$1 == k":" { print $2; found=1 } END { if (!found) print 0 }' \
    <<< "$status_raw"
}

# Last completion timestamp: parse 'Scrub started: ... finished: ...' line if
# present, otherwise 0. The non -R form has the human-readable line; pull from there.
finished_epoch="$(/usr/bin/btrfs scrub status "$mount" 2>/dev/null \
  | awk -F': ' '/Scrub started/ { gsub(/^[[:space:]]+/, "", $3); print $3 }' \
  | xargs -I{} date -d "{}" +%s 2>/dev/null || echo 0)"

uuid="$(awk '/^UUID:/ { print $2 }' <<< "$status_raw")"

cat > "$tmp_file" <<EOF
# HELP btrfs_scrub_last_finished_timestamp_seconds Unix time when the last scrub finished. 0 if never.
# TYPE btrfs_scrub_last_finished_timestamp_seconds gauge
btrfs_scrub_last_finished_timestamp_seconds{mountpoint="$mount",uuid="$uuid"} ${finished_epoch:-0}
# HELP btrfs_scrub_data_bytes_scrubbed_total Bytes of data scrubbed in the last scrub.
# TYPE btrfs_scrub_data_bytes_scrubbed_total counter
btrfs_scrub_data_bytes_scrubbed_total{mountpoint="$mount",uuid="$uuid"} $(field data_bytes_scrubbed)
# HELP btrfs_scrub_errors_total Errors observed by the last scrub, by class.
# TYPE btrfs_scrub_errors_total counter
btrfs_scrub_errors_total{mountpoint="$mount",uuid="$uuid",class="read"} $(field read_errors)
btrfs_scrub_errors_total{mountpoint="$mount",uuid="$uuid",class="csum"} $(field csum_errors)
btrfs_scrub_errors_total{mountpoint="$mount",uuid="$uuid",class="verify"} $(field verify_errors)
btrfs_scrub_errors_total{mountpoint="$mount",uuid="$uuid",class="super"} $(field super_errors)
btrfs_scrub_errors_total{mountpoint="$mount",uuid="$uuid",class="uncorrectable"} $(field uncorrectable_errors)
btrfs_scrub_errors_total{mountpoint="$mount",uuid="$uuid",class="corrected"} $(field corrected_errors)
EOF

chmod 0644 "$tmp_file"
mv -f "$tmp_file" "$out_file"
trap - EXIT
```

**Wiring into the existing service** — extend `proxmox-fs.yaml` so the unit
gains `ExecStopPost=` (runs once after every scrub finish, success or failure):

```yaml
[Service]
Type=oneshot
ExecStart=/usr/bin/btrfs scrub start -B /mnt/media
ExecStopPost=/usr/local/sbin/btrfs-scrub-textfile.sh /mnt/media
IOSchedulingClass=idle
CPUSchedulingPolicy=idle
Nice=19
```

**Plus** a separate fast-cadence timer so the "age since last scrub" metric
stays fresh between monthly runs (otherwise the gauge only updates once a
month and the scrub-age alert wouldn't fire until *after* the next scrub).

```yaml
# btrfs-scrub-textfile.timer — every 15 min
[Timer]
OnBootSec=2min
OnUnitActiveSec=15min
```

The fast timer reads on-disk scrub state (cheap, no I/O on the FS) and
overwrites the .prom file. Same script, same metrics — the only thing that
changes between fires is `last_finished_timestamp_seconds` going stale.

### 3. PrometheusRules

New file: `k8s/infrastructure/configs/btrfs-scrub-rules.yaml` — a
`PrometheusRule` CR picked up by the kube-prometheus-stack operator.

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: btrfs-scrub
  labels:
    release: kube-prometheus-stack  # operator's selector — confirm
spec:
  groups:
    - name: btrfs-scrub
      rules:
        - alert: BtrfsScrubServiceFailed
          expr: node_systemd_unit_state{name="btrfs-scrub-media.service",state="failed"} == 1
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "btrfs scrub service failed on {{ $labels.nodename }}"
            description: "btrfs-scrub-media.service is in failed state. Check `journalctl -u btrfs-scrub-media.service` on {{ $labels.nodename }}."

        - alert: BtrfsScrubFoundErrors
          expr: btrfs_scrub_errors_total{class=~"uncorrectable|csum|verify"} > 0
          for: 1m
          labels:
            severity: critical
          annotations:
            summary: "btrfs scrub on {{ $labels.mountpoint }} found {{ $labels.class }} errors"
            description: "Last scrub on {{ $labels.mountpoint }} reported {{ $value }} {{ $labels.class }} error(s). This indicates bitrot or hardware issues — investigate immediately."

        - alert: BtrfsScrubStale
          # No scrub completion in >40 days (monthly cadence + buffer)
          expr: |
            (time() - btrfs_scrub_last_finished_timestamp_seconds) > 40 * 86400
            or btrfs_scrub_last_finished_timestamp_seconds == 0
          for: 1h
          labels:
            severity: warning
          annotations:
            summary: "btrfs scrub on {{ $labels.mountpoint }} is stale"
            description: "No successful scrub on {{ $labels.mountpoint }} in over 40 days (or never). Timer may be broken."

        - alert: BtrfsDeviceErrors
          # Device-level errors from `btrfs device stats` — independent of scrub,
          # caught by node-exporter's built-in btrfs collector
          expr: increase(node_btrfs_device_errors_total[1h]) > 0
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "btrfs device errors on {{ $labels.device }} ({{ $labels.type }})"
            description: "{{ $labels.type }} errors increased on {{ $labels.device }} (uuid {{ $labels.uuid }}) in the last hour."
```

The `release: kube-prometheus-stack` selector label depends on the operator's
`ruleSelector`. Verify by reading the existing prometheus CR or chart values
before applying — current convention in this repo can be checked by grepping
existing PrometheusRule resources.

### 4. Grafana

Two options, in order of effort:

**Option A (preferred for now): extend the existing dashboard.** Add a row to
the homelab overview dashboard (or wherever Proxmox health currently lives)
with three panels:

1. **Stat — "Days since last scrub"**
   `(time() - btrfs_scrub_last_finished_timestamp_seconds{mountpoint="/mnt/media"}) / 86400`
   thresholds: green <30, yellow 30–40, red >40 or `==Inf` (never run).

2. **Stat — "Scrub errors (last run)"**
   `sum by (mountpoint) (btrfs_scrub_errors_total{class=~"uncorrectable|csum|verify"})`
   green 0, red >0.

3. **Time series — "Btrfs device errors"**
   `node_btrfs_device_errors_total` broken out by `type`. Shows cumulative
   counters; useful for spotting trends (e.g. a flaky disk slowly accumulating
   read errors between scrubs).

**Option B (later): standalone "Storage Health" dashboard.** Pull in btrfs
allocation/usage from the built-in collector, ZFS metrics if/when introduced,
and the scrub panels above. Belongs alongside the rest of the
observability-journey work — not worth doing for a single mountpoint.

Provisioning matches the existing pattern: drop the JSON into
`k8s/infrastructure/configs/grafana-dashboards/`, add it to the kustomization,
the sidecar picks it up via the `grafana_dashboard: "1"` label.

### 5. Alertmanager

Nothing new required — the alerts above use standard `severity` labels
(`warning`, `critical`) which should already match existing Alertmanager
routes. If routing is currently default-only, that's a separate piece of work
worth tackling alongside the broader observability journey, not gated on this
plan.

## Order of Operations

1. Re-run `proxmox-fs.yaml` with the path fix → confirm a manual scrub
   completes successfully (`systemctl start btrfs-scrub-media.service` then
   `btrfs scrub status /mnt/media`). This validates the foundation before
   layering monitoring on top.
2. Add the textfile script + `ExecStopPost` + 15-min timer in `proxmox-fs.yaml`.
   Re-run, confirm `/var/lib/node_exporter/btrfs_scrub.prom` exists and metrics
   appear in Prometheus (`{__name__=~"btrfs_scrub.*"}`).
3. Apply `PrometheusRules`. Trigger `BtrfsScrubServiceFailed` deliberately
   (e.g. break the unit temporarily) to confirm end-to-end alert delivery.
4. Add the Grafana panels.

## Open Questions / Verifications Needed

- **Textfile collector dir**: confirm the actual path on the host with
  `systemctl cat node_exporter | grep textfile.directory` — the role default
  has shifted across versions. Lock the script's `TEXTFILE_DIR` to whatever
  it actually is rather than assuming.
- **PrometheusRule selector label**: confirm what label the kube-prometheus-stack
  operator's `ruleSelector` matches in this cluster.
- **Scrub finish timestamp parsing**: the `date -d` parse of the human-readable
  "Scrub started" line is the fragile bit. Worth validating against a real
  finished scrub before relying on the `BtrfsScrubStale` alert. If it turns
  out to be unreliable across btrfs-progs versions, fall back to recording
  the timestamp ourselves: write `date +%s > /var/lib/node_exporter/btrfs_scrub_last_run`
  in `ExecStopPost=` and read it from the script.
