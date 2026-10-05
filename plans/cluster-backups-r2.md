# Off-site Cluster Backups on Cloudflare R2

Off-site, encrypted, monitored backups of everything needed to rebuild the k8s
cluster with its data: the OpenTofu state (cluster secrets), scheduled `etcd`
snapshots, and Longhorn volume backups. All of it goes to Cloudflare R2.

## Rationale

Today, nothing in the cluster is backed up off-host:

- **Cluster secrets only exist on the Mac.** `talos_machine_secrets` (the
  cluster PKI plus the key Talos uses to encrypt Secrets inside `etcd`) lives only in
  `Terraform-OpenTofu/terraform.tfstate`, which is local and gitignored. Without
  it, even a perfect `etcd` snapshot can't bring back a working cluster.
- **`etcd` has no snapshots.** The 2:1 control-plane split leaves a full copy
  on `prox2`, but that's a replica, not a backup. It faithfully replicates bad writes,
  deletes and corruption, and it disappears if both hosts are lost.
- **Volume data has no backups.** Longhorn keeps 2 replicas across both hosts,
  which protects against losing one disk or host, not against losing both,
  accidental deletion, or a corrupted volume.

Git + Flux recreate everything *declared*, but not state that only exists in
the cluster (app data, PV bindings, Longhorn volume records).

### Why R2

- **Effectively free at this size.** See [Cost](#cost).
- **No egress fees.** A full restore costs nothing.
- **Already a Cloudflare customer.** Same account as DNS and the DNS-01 tokens,
  so no new vendor.
- **S3-compatible.** talos-backup, Longhorn and OpenTofu's `s3` backend all
  work against it. Moving to AWS S3 later is just a change of endpoint and credentials.

## Goals

1. Cluster can be rebuilt from scratch **without the Mac**: state, secrets and
   keys are all recoverable from off-site storage plus a password manager.
2. Point-in-time `etcd` snapshots, encrypted before they leave the cluster.
3. Daily backups of volumes holding data that can't be regenerated.
4. Alerts when any backup stops succeeding, not just when one fails loudly.
5. A written, *tested* restore runbook.

## Current State

```
Mac (local only)
├── Terraform-OpenTofu/terraform.tfstate   ← talos_machine_secrets, cluster PKI
└── ~/.ssh/keys/sops-age.txt               ← age private key (SOPS + agenix)

k8s cluster
├── etcd: 2 members on prox, 1 on prox2 — no snapshots
└── Longhorn (2 replicas, one per host) — no backup target
```

## Target State

```
Cloudflare R2
├── homelab-tofu-state        ← OpenTofu state, encrypted client-side (AES-GCM)
├── homelab-etcd-backups      ← age-encrypted snapshots; lifecycle rule expires after 14 days
└── homelab-longhorn-backups  ← Longhorn block-level incremental backups; Longhorn owns retention

Password manager
├── age private key
└── OpenTofu state passphrase

k8s cluster
├── CronJob talos-backup (every 6h) → homelab-etcd-backups
├── Longhorn backup target → homelab-longhorn-backups
│     └── RecurringJob "daily" (opt-in group via PVC labels)
└── PrometheusRule: backup failed / backup stale
```

## Plan

### 1. R2 buckets and credentials

Create the three buckets in the Cloudflare dashboard, plus one **R2 API token per
consumer**, each scoped to its own bucket with *Object Read & Write*. That way a
leaked token for one consumer can't touch another consumer's bucket.

| Bucket | Token consumer | Lifecycle rule |
|---|---|---|
| `homelab-tofu-state` | OpenTofu (Mac) | none |
| `homelab-etcd-backups` | talos-backup (in-cluster) | delete objects after 14 days |
| `homelab-longhorn-backups` | Longhorn (in-cluster) | **none** |

**Never put a lifecycle rule on the Longhorn bucket.** Longhorn backups are
incremental and share 2 MB blocks across backups, so deleting objects by age
would corrupt newer backups that still reference old blocks. Longhorn prunes
its own data based on each `RecurringJob`'s `retain`.

The state bucket has to exist before OpenTofu can use it, so it's created by hand.
Whether to codify the other two in OpenTofu is an open question (see below).

### 2. Remote, encrypted OpenTofu state

Move the state to R2 and turn on OpenTofu's native state encryption in the
same change, so the state never sits in the bucket unencrypted.

```hcl
terraform {
  backend "s3" {
    bucket       = "homelab-tofu-state"
    key          = "homelab/terraform.tfstate"
    region       = "auto"
    endpoints    = { s3 = "https://<ACCOUNT_ID>.r2.cloudflarestorage.com" }
    use_lockfile = true
    # R2 isn't AWS: skip the AWS-only account/region/STS checks (verify exact set)
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    use_path_style              = true
  }

  encryption {
    key_provider "pbkdf2" "state" {
      passphrase = var.state_passphrase
    }
    method "aes_gcm" "state" {
      keys = key_provider.pbkdf2.state
    }
    method "unencrypted" "migrate" {}

    state {
      method = method.aes_gcm.state
      fallback { method = method.unencrypted.migrate } # remove after first apply, then set enforced = true
    }
    plan {
      method = method.aes_gcm.state
      fallback { method = method.unencrypted.migrate }
    }
  }
}
```

- **Passphrase:** store it SOPS-encrypted in the repo (like the Proxmox
  tokens). The `deploy-*` just recipes export it as `TF_VAR_state_passphrase`,
  and a copy also goes in the password manager. The backend credentials (R2 token) follow
  the same pattern via `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`.
- **Migration:** `tofu init -migrate-state`, run a `tofu plan` and confirm no
  changes, check the object in R2 is ciphertext, then remove the `fallback` blocks and set
  `enforced = true`. Delete the local `terraform.tfstate*` files only after that.

### 3. `etcd` snapshots with talos-backup

[talos-backup](https://github.com/siderolabs/talos-backup) is Sidero's official
tool. A CronJob takes the snapshot through the Talos API, age-encrypts it, and uploads it to S3.

**Talos side.** Add a control-plane-only machine config patch in `talos.tf`
(next to the existing `controlplane` `config_patches`). This is the Talos
v1.12 form. On v1.14+ it moves to a `KubeTalosAPIAccessConfig` document.

```yaml
machine:
  features:
    kubernetesTalosAPIAccess:
      enabled: true
      allowedRoles: [os:etcd:backup]
      allowedKubernetesNamespaces: [talos-backup]
```

**Cluster side.** Add `k8s/infrastructure/controllers/talos-backup.yaml` with:

- a `Namespace` `talos-backup`;
- a Talos `ServiceAccount` (`talos.dev/v1alpha1`, `spec.roles: [os:etcd:backup]`),
  which Talos turns into a Secret holding a scoped talosconfig;
- the `CronJob`, based on upstream's `cronjob.sample.yaml`:
  - schedule `0 */6 * * *`;
  - env `BUCKET`, `CUSTOM_S3_ENDPOINT`, `AWS_REGION=auto`, `USE_PATH_STYLE=true`,
    `CLUSTER_NAME`, `ENABLE_COMPRESSION=true`;
  - `AGE_RECIPIENT_PUBLIC_KEY` = the existing SOPS age public key (one key for
    the whole homelab);
  - the R2 credentials from a Secret;
- `talos-backup-r2.sops.yaml` holding `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`.

Retention is the bucket's lifecycle rule. talos-backup doesn't prune.

### 4. Longhorn backups

**Backup target.** Add to the Longhorn HelmRelease values:

```yaml
defaultBackupStore:
  backupTarget: s3://homelab-longhorn-backups@auto/
  backupTargetCredentialSecret: longhorn-r2
  # Each poll lists the bucket; R2 counts those as billable Class A operations
  pollInterval: "3600"
```

`longhorn-r2.sops.yaml` (in `longhorn-system`) holds `AWS_ACCESS_KEY_ID`,
`AWS_SECRET_ACCESS_KEY` and `AWS_ENDPOINTS`.

**Schedule.** Add one `RecurringJob` in a named group rather than `default`, so
backups are opt-in per PVC:

```yaml
apiVersion: longhorn.io/v1beta2
kind: RecurringJob
metadata:
  name: daily-backup
  namespace: longhorn-system
spec:
  task: backup
  cron: "0 3 * * *"
  groups: [daily]
  retain: 7
  concurrency: 2
```

Opt PVCs in through labels in their manifests. That keeps the decision in Git next to the
app.

```yaml
metadata:
  labels:
    recurring-job.longhorn.io/source: enabled
    recurring-job-group.longhorn.io/daily: enabled
```

| Back up | Skip (expendable or regenerable) |
|---|---|
| `karakeep-data-pvc`, `stash-config-pvc`, `qui-config-pvc`, `uptime-kuma-data-pvc`, `executor-data-pvc`, `e-store/data-mysql-0` | Prometheus TSDB (~85% of all data, rewritten during compaction, so every incremental backup is close to a full one), Alertmanager, Grafana (dashboards come from Git), `karakeep-meilisearch-pvc` (rebuildable, see `docs/karakeep.md`), `stash-generated-pvc` |

Weekly backups with longer retention can be added later as a second job and group if 7
days turns out to be too short.

### 5. Alerting

The Prometheus rule selectors are already unrestricted
(`ruleSelectorNilUsesHelmValues: false`), so a `PrometheusRule` in
`k8s/infrastructure/configs/` gets picked up without any labels.

- **`EtcdBackupStale`**:
  `time() - kube_cronjob_status_last_successful_time{cronjob="talos-backup"} > 13 * 3600`
  (two missed runs). The stock `KubeJobFailed` already covers loud failures.
- **Longhorn backup failure/staleness:** enable the chart's
  `metrics.serviceMonitor` (currently commented out), then alert on Longhorn's
  backup metrics. The exact metric depends on what Longhorn exposes (see open questions).

### 6. Key custody

Put the age private key (`~/.ssh/keys/sops-age.txt`) and the state passphrase
in the password manager. With those two items plus R2 access, the cluster can be
recovered from any machine.

### 7. Disaster-recovery runbook and restore drill

Write `docs/disaster-recovery.md` covering:

1. **State:** fetch the state from R2 using the passphrase. The cluster secrets are in it.
2. **`etcd`:** download the latest snapshot, `age -d` it, recreate the
   control plane with the same secrets, then
   `talosctl bootstrap --recover-from=./db.snapshot`.
3. **Volumes:** restore Longhorn backups into new volumes and rebind the PVCs.

Drill it at least once before trusting it:

- **Longhorn (low risk, on the live cluster):** restore a backup of
  `uptime-kuma-data-pvc` into a new volume, mount it in a scratch pod, and
  check the data.
- **`etcd`:** decrypt a snapshot and check its integrity
  (`etcdutl snapshot status`). Then do a full restore into a throwaway cluster
  built from the same secrets bundle.

## Cost

R2's free tier (10 GB-month of storage, 1M Class A and 10M Class B operations per
month, free egress) covers all of this:

| Item | Estimate |
|---|---|
| Longhorn (opted-in PVCs ≈ 1 GB today, 7 dailies) | ~1–2 GB |
| `etcd` (every 6h, 14 days = 56 snapshots, zstd-compressed) | ~1–2 GB (size to confirm) |
| OpenTofu state | < 1 MB |
| Operations (uploads plus hourly Longhorn polling) | well under the free tier |

Above the free tier, storage costs $0.015/GB-month. Including Prometheus would
add about 30–60 GB and push the total over the free tier, which is one more reason to skip it.

## Order of Operations

1. Save the age key and a new state passphrase in the password manager.
2. Create the buckets, lifecycle rule and scoped tokens (step 1).
3. Migrate the state to R2 with encryption (step 2). Confirm `tofu plan` is
   clean, then enforce encryption.
4. Apply the Talos patch (`just deploy-apply`), then ship talos-backup (step 3).
   Trigger a manual run (`kubectl create job --from=cronjob/talos-backup`) and
   check an encrypted object lands in R2.
5. Set up the Longhorn backup target and `RecurringJob`, then label the PVCs (step 4).
   Run a manual backup of one volume from the UI first.
6. Add the alerts (step 5). Check they fire by temporarily suspending the CronJob.
7. Write the runbook and run both drills (step 7).
8. Docs: add a `docs/decisions.md` entry and a README section on backups, and
   update the roadmap.

## Open Questions / Verifications Needed

- **R2 and `use_lockfile`:** OpenTofu's native S3 locking relies on conditional
  writes (`If-None-Match`). Confirm R2 supports them. Also confirm the exact set of
  `skip_*` / checksum flags R2 needs with the current OpenTofu version.
- **No object versioning on R2 (verify).** If that's true, a bad state write
  can't be rolled back from the bucket. Options: accept it (the state is small
  and fully reproducible except for secrets), or have the `deploy-apply` recipe pull a
  dated copy of the state before each apply.
- **Longhorn with region `auto`:** confirm Longhorn accepts `@auto` in the
  backup target URL with R2. Fall back to `@us-east-1` (R2 treats it as an alias) if not.
- **`etcd` snapshot size:** check the DB size (`talosctl -n 10.20.30.60 etcd status`)
  before settling on the 6h / 14-day schedule.
- **talos-backup image:** pin a release tag of
  `ghcr.io/siderolabs/talos-backup` (check the latest release when
  implementing).
- **Longhorn backup metrics:** confirm which metrics expose backup state or
  age once the ServiceMonitor is enabled. If none gives "time since last successful
  backup", alert on failed backup state instead.
- **Codify buckets in OpenTofu?** Adding the `cloudflare` provider would make
  the backup buckets and lifecycle rule declarative. The state bucket stays manual either
  way (it's what the state lives in), and R2 token creation through the provider is
  awkward, so it's not obviously worth it for two buckets.
- **Ransomware-style protection:** in-cluster tokens can delete backups. R2
  bucket locks could make `etcd` snapshots undeletable for N days. That doesn't work
  for the Longhorn bucket, where Longhorn has to prune its own data.
- **Restore drill for `etcd`:** decide how to build a throwaway cluster from the
  same secrets bundle, either as a local Docker Talos cluster or as a second set of Proxmox VMs.
