# nixos-ct as an Unprivileged LXC

Convert `nixos-ct` (CT 1000 on `prox`) from a privileged to an unprivileged
container, using a custom ID map so container UID/GID 1000 (`murtadha`) is
still host UID/GID 1000 and the bind-mounted media stays accessible.

## Rationale

In a privileged container, container root *is* host root. Anything that
breaks out of the container (a kernel bug, a misconfigured device, a
compromised service running as root) owns the Proxmox host, and with it every
other guest. nixos-ct runs a dozen network-facing services plus the Nix
remote builder, so it's the most exposed guest on `prox`.

An unprivileged container runs everything inside a user namespace: container
UID 0 is host UID 100000, which has no rights on the host. The only reason
nixos-ct is privileged today is that the bind mounts (`/mnt/media`,
`/mnt/usb-hdd`, `/mnt/bulk`) are owned by host UID 1000, which the default
unprivileged map would show as `nobody`. An `lxc.idmap` that passes just
UID/GID 1000 through 1:1 fixes that without giving up the namespace. This is
the standard Proxmox pattern for bind mounts into unprivileged containers.

Side benefits:

- Nesting can move from Ansible into Terraform: an API token can set it on
  unprivileged containers (as `nixos-ct-2` already does).
- The container loses write access to `/mnt/media/proxmox` (the `media-lv`
  Proxmox storage: VM images and backups, owned by host root), which it has
  no business touching.

## Goals

1. nixos-ct runs unprivileged, with only UID/GID 1000 mapped 1:1 to the host.
2. Every service, the bind mounts, Tailscale (TUN) and the remote builder
   (Nix sandbox, which needs nesting) keep working.
3. The container and its ID map are declared in Terraform. Ansible only does
   what the API can't (bind mounts, TUN passthrough, `/etc/subuid`).
4. Existing service state in the rootfs survives (no fresh reinstall).

## Non-goals

- GPU passthrough for Jellyfin. The container has no `/dev/dri` today. If
  it's added later, use `device_passthrough` with a `gid` for the render group.
- Changing `nixos-ct-2`. It's already unprivileged with the default map.

## Current state

| Item | Value |
| --- | --- |
| Proxmox | 9.2 on `prox` |
| Host `/etc/subuid` and `/etc/subgid` | `root:100000:65536` (no entry for 1000) |
| Bind mounts | `mp0` `/mnt/media`, `mp1` `/mnt/usb-hdd`, `mp2` `/mnt/bulk`, all `1000:1000 0750` on the host |
| Devices / features | `dev0: /dev/net/tun`, `nesting=1` (both set by Ansible) |
| Rootfs | `local:1000/vm-1000-disk-0.raw`, 32G, about 16G used |
| Services writing to bind mounts | jellyfin, qbittorrent, sabnzbd, sonarr, syncthing, all as `murtadha` (1000) |

## Target ID map

The same map applies to both `uid` and `gid`:

| Container IDs | Host IDs | Size | Covers |
| --- | --- | --- | --- |
| 0–999 | 100000–100999 | 1000 | root, system users |
| 1000 | 1000 | 1 | `murtadha` (bind-mount owner) |
| 1001–65535 | 101001–165535 | 64535 | `nixbld*`, systemd DynamicUsers, everything else |

The host must allow root to delegate host ID 1000: add `root:1000:1` to both
`/etc/subuid` and `/etc/subgid` (alongside the existing `root:100000:65536`).

## Changes

### Ansible: `ansible/playbooks/proxmox-nixos-ct.yaml` (pve-host-1 play)

- Add `ansible.builtin.lineinfile` tasks putting `root:1000:1` in
  `/etc/subuid` and `/etc/subgid`.
- Drop the "Enable nesting feature" task (it moves to Terraform).
- Update the header comment: nesting is no longer an imperative task here.

### Terraform: `Terraform-OpenTofu/lxc-nixos.tf`

- `unprivileged = true`, plus `features { nesting = true }`.
- `idmap` blocks for the table above. The provider writes them as
  `lxc.idmap` lines over its SSH connection, which `providers.tf` already
  configures. A `dynamic "idmap"` over a local list of the three ranges ×
  `["uid", "gid"]` keeps it to one place.
- Rewrite the `unprivileged` comment (why the idmap exists) and the
  bind-mount note (nesting is no longer restricted).

### Nix: `Nix/hosts/nixos-ct/default.nix`

- Drop `privileged = true` from `proxmoxLXC` (the default, `false`, skips the
  debugfs mount and installs the `ping` capability wrapper). This works in
  either mode, so it can ship ahead of the migration.

### Docs

- `README.md` (the "privileged LXC container" bullet under step 4) now
  describes the unprivileged + idmap setup.
- `docs/decisions.md`: a new entry recording the switch and why.
- `docs/decisions.md` (the `nixos-ct-2` entry, "Unprivileged, unlike
  `nixos-ct`"): adjust the contrast.

## Migration runbook

`unprivileged` can't be flipped on an existing container, and letting
Terraform replace it would wipe the rootfs. So the conversion is a backup and
an unprivileged restore on the host, and Terraform is then brought in line
with the result.

Expect about 15–30 minutes of downtime for every nixos-ct service. LAN DNS
only survives it if clients have `nixos-ct-2` (10.20.30.51) as a secondary
resolver. Check that before starting (see `docs/tailscale-setup.md` for the
tailnet side).

### 0. Prep (no downtime)

1. Ship the Nix change (`privileged = true` removed) with `just nix-deploy`.
2. Run the Ansible playbook so `/etc/subuid` and `/etc/subgid` have
   `root:1000:1`. This is harmless while the container is still privileged.
3. Optionally shrink the backup by running `nix-collect-garbage -d` in the
   container, and clean out orphaned state from services no longer on this
   host (e.g. `/mnt/media/stash`). Inspect `/var/lib` for others first.
   Anything left that isn't owned by 1000 will show up as `nobody` afterwards.

### 1. Backup (on `prox`)

```sh
pct stop 1000
vzdump 1000 --mode stop --storage media-lv --compress zstd
```

Keep this archive until the rollback window closes.

### 2. Restore as unprivileged

```sh
pct restore 1000 /mnt/media/proxmox/dump/vzdump-lxc-1000-<timestamp>.tar.zst \
  --storage local --unprivileged 1 --force 1
pct config 1000   # mp0–mp2, dev0 and nesting must still be there
```

The restore shifts rootfs ownership with the *default* map (+100000), so
container UID 1000 files now belong to host UID 101000.

### 3. Apply the custom map and fix ownership

Append the six `lxc.idmap` lines to `/etc/pve/lxc/1000.conf`, exactly as
Terraform will write them:

```
lxc.idmap: u 0 100000 1000
lxc.idmap: g 0 100000 1000
lxc.idmap: u 1000 1000 1
lxc.idmap: g 1000 1000 1
lxc.idmap: u 1001 101001 64535
lxc.idmap: g 1001 101001 64535
```

Then hand the shifted `murtadha` files back to host ID 1000. `-xdev` keeps
`find` on the rootfs and out of the bind mounts, which are already correct:

```sh
pct mount 1000
root=/var/lib/lxc/1000/rootfs
find $root -xdev -uid 101000 -exec chown -h 1000 {} +
find $root -xdev -gid 101000 -exec chgrp -h 1000 {} +
find $root -xdev \( -uid 101000 -o -gid 101000 \) | wc -l   # expect 0
pct unmount 1000
pct start 1000
```

### 4. Verify

In the container:

- `systemctl is-system-running` reports `running` and `systemctl --failed` is
  empty.
- `sudo -u murtadha touch /mnt/media/.idmap-test` works, and on the host
  `stat -c %u:%g /mnt/media/.idmap-test` shows `1000:1000`. Then delete it.
- `tailscale status` is up and the subnet route is still advertised.

From the host, `ps -o uid= -C AdGuardHome` shows a UID above 100000 (the
namespace is real).

From the Mac:

- `dig jellyfin.home.murtadha.dev @10.20.30.50` returns `10.20.30.50`.
- Every `https://<svc>.home.murtadha.dev` vhost answers.
- The remote builder can still run sandboxed builds. Force a fresh
  derivation, then remove the `result` link:

  ```nu
  nix build --impure --expr 'derivation { name = "idmap-test"; system = "x86_64-linux"; builder = "/bin/sh"; args = [ "-c" "echo ${toString builtins.currentTime} > $out" ]; }'
  ```

### 5. Converge Terraform

Commit the Terraform/Ansible changes, then run `tofu plan`. It must show **no
replacement** of `proxmox_virtual_environment_container.nixos`. In-place
updates (features, idmap) are fine. If the provider insists on replacing it,
re-adopt the container instead of applying:

```sh
tofu state rm proxmox_virtual_environment_container.nixos
tofu import proxmox_virtual_environment_container.nixos prox/1000
```

Re-plan until it's clean (or only in-place), then `tofu apply`.

## Rollback

Until the backup is deleted:

```sh
pct stop 1000
pct restore 1000 /mnt/media/proxmox/dump/vzdump-lxc-1000-<timestamp>.tar.zst --storage local --force 1
```

This brings back the privileged container exactly as it was. Revert the
Terraform change and `tofu plan` to confirm no drift. The `root:1000:1`
subuid/subgid entries are harmless to leave.

## Risks and open questions

- **Files on the bind mounts not owned by 1000** show up as `nobody` and
  become read-only (or unreadable) inside the container. Today that's only
  `/mnt/media/proxmox` (intended) and the orphaned `/mnt/media/stash`.
- **Future services running as their own user** (like the old Stash module's
  `stash` user) can't own files on the bind mounts. They must run as
  `murtadha` or reach them through group 1000, which `stash.nix` already does.
- **Whether `pct restore` honours an archived `lxc.idmap`** doesn't matter
  here: step 3 checks for and fixes the shifted owner either way.
