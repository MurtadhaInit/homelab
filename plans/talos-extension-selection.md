# Talos Extension Selection: Exact Names Over Substring Matching

Replace the substring-based `filters.names` lookup that feeds the Talos Image
Factory schematic with an exact list, so the image carries precisely the
extensions we asked for and nothing else.

## Rationale

`data.talos_image_factory_extensions_versions` matches its `filters.names`
entries as **substrings**, not exact names. Asking for `iscsi-tools` therefore
resolves to two extensions:

```
iscsi-tools           v0.2.0
trident-iscsi-tools   v0.0.1
```

`trident-iscsi-tools` is NetApp Trident's iSCSI tooling. Nothing in this cluster
uses Trident — Longhorn is the only storage provisioner — so it has been riding
along in every image since the filter was written. It is inert rather than
harmful, but it is not something we chose, and a schematic that silently
contains more than it was asked for is the kind of thing that quietly grows.

This is worth fixing on principle rather than urgency: the schematic is the
single declaration of what the OS image *is*, and it should be exact.

## Non-goal: splitting the microcode extensions per host

The schematic also carries **both** `amd-ucode` and `intel-ucode`, and both land
on every node regardless of which host it runs on. This is deliberate — record
it here so it does not get "fixed" later:

- The kernel's early microcode loader matches on CPU vendor and applies only the
  matching blob. The other sits unused in the initramfs. Verified on
  `talos-worker-2` (Intel N150), which enables both cleanly:

  ```
  [talos] [initramfs] enabling system extension intel-ucode 20260227
  [talos] [initramfs] enabling system extension amd-ucode 20260309
  ```

- This is how generic distro install/live images work too — ship both vendors,
  let the kernel pick.
- The size cost is a few MB against a 4.45 GB raw disk image.
- Splitting them would mean one schematic per host, which in turn means two
  `talos_image_factory_schematic` resources, two URL data sources, per-host
  `file_id` wiring, and — the part that actually hurts — **two different
  installer images**, so `talos_upgrade_image` becomes per-host and upgrades
  stop being one uniform command.

Revisit only if image size ever genuinely matters (PXE, constrained boot media).

## Current State

```
vm-talos.tf
├── data.talos_image_factory_extensions_versions.this
│     filters.names = [qemu-guest-agent, amd-ucode, intel-ucode,
│                      iscsi-tools, util-linux-tools]      ← substring match
├── talos_image_factory_schematic.this
│     officialExtensions = data...extensions_info.*.name   ← 6 entries, not 5
└── proxmox_download_file.talos_image[host]  (one per Talos host)

resolved schematic contents (6):
  siderolabs/amd-ucode          siderolabs/intel-ucode
  siderolabs/iscsi-tools        siderolabs/trident-iscsi-tools   ← unwanted
  siderolabs/qemu-guest-agent   siderolabs/util-linux-tools

live schematic IDs
  talos-worker-2   7ee8c76d…   (new image, built with intel-ucode)
  all other nodes  debb35ba…   (older image, amd-ucode only)
```

Note the nodes are already inconsistent: only `talos-worker-2` was created from
the current schematic. Everything else picks up a new schematic on its next
`talosctl upgrade`, not before — `ignore_changes = [disk[0].file_id]` keeps
running VMs off a changed image.

## Plan

### Option A (preferred): keep the data source, intersect on exact names

Preserves the existing intent — "declare what we want, let the provider resolve
it for this Talos version" — while making the selection exact. A typo still
fails at plan time rather than at image-build time, which is the main thing the
data source buys us.

```hcl
locals {
  # Exact official extension names. The factory resolves the right version for
  # var.talos_version, so no versions are pinned here.
  talos_extensions = [
    "siderolabs/qemu-guest-agent",
    "siderolabs/amd-ucode",       # prox  (AMD Ryzen 5 5600H)
    "siderolabs/intel-ucode",     # prox2 (Intel N150)
    "siderolabs/iscsi-tools",     # for Longhorn
    "siderolabs/util-linux-tools" # for Longhorn
  ]
}

data "talos_image_factory_extensions_versions" "this" {
  talos_version = var.talos_version
  filters = {
    names = local.talos_extensions
  }
}

resource "talos_image_factory_schematic" "this" {
  schematic = yamlencode({
    customization = {
      systemExtensions = {
        # `filters.names` matches substrings, so the data source over-returns
        # (asking for iscsi-tools also yields trident-iscsi-tools). Intersect
        # with the exact list to get only what we declared.
        officialExtensions = [
          for e in data.talos_image_factory_extensions_versions.this.extensions_info :
          e.name if contains(local.talos_extensions, e.name)
        ]
      }
    }
  })
}
```

### Option B: drop the data source entirely

Simpler to read, one fewer moving part:

```hcl
resource "talos_image_factory_schematic" "this" {
  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = local.talos_extensions
      }
    }
  })
}
```

The cost is losing plan-time validation — a misspelled extension would be
accepted by OpenTofu and only fail when the Factory tries to build the image.
Given how rarely this list changes, that is a defensible trade, but Option A is
the smaller behavioural change.

## Consequences

Either option produces a **new schematic ID**, which cascades:

1. `proxmox_download_file.talos_image["prox"]` and `["prox2"]` are both replaced
   — a ~4.45 GB re-download per host. Check free space on prox's `local`
   beforehand; it has historically run tight.
2. The `talos_upgrade_image` output changes to the new installer image.
3. **No running node changes.** `ignore_changes = [disk[0].file_id]` protects
   them; nodes only adopt the new schematic when explicitly upgraded.

Because of (3), doing this on its own achieves nothing observable — the images
sit on disk unused until an upgrade. **Fold it into the next Talos upgrade** so
the schematic change and the node rollout happen as one intentional operation,
and every node lands on the same schematic ID at the end (fixing the current
`7ee8c76d` / `debb35ba` split as a side effect).

## Order of Operations

1. Make the code change; `tofu plan` should show exactly: schematic updated
   in-place, both `talos_image_factory_urls` re-read, both
   `proxmox_download_file.talos_image[*]` replaced, `talos_upgrade_image`
   changed. **Nothing touching `proxmox_virtual_environment_vm.talos`** — if a
   VM shows up in the plan, stop and work out why.
2. `tofu apply` — images land on both hosts.
3. Upgrade nodes one at a time with the new installer image, control planes
   last, waiting for `Ready` and for Longhorn volumes to return to `healthy`
   between each (a worker upgrade takes its Longhorn replica offline).
4. Confirm every node reports the same schematic ID.

## Verification

```nu
# every node on one schematic, exactly 5 extensions + the schematic entry
talosctl -n 10.20.30.60,10.20.30.61,10.20.30.62,10.20.30.70,10.20.30.71 get extensions

# trident should be absent
talosctl -n 10.20.30.70 get extensions | find trident   # expect no rows

# microcode still enabling on both vendors' hosts
talosctl -n 10.20.30.71 dmesg | find ucode
```

## Open Questions / Verifications Needed

- **Does `contains()` behave as expected against `extensions_info[*].name`?**
  The names carry the `siderolabs/` prefix (confirmed — the generated schematic
  lists `siderolabs/amd-ucode` etc.), so `local.talos_extensions` must use the
  prefixed form. Worth a `tofu console` check before applying.
- **Free space on prox's `local`** before triggering a 4.45 GB re-download — it
  was at 80% when the second host was first wired up.
- Whether to take the opportunity to bump `var.talos_version` at the same time,
  since a node rollout is happening either way.
