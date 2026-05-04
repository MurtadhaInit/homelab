# nixos-ct as a Nix Remote Builder

Promote the existing `nixos-ct` Proxmox LXC to double as a Nix remote builder
for the Mac controller, so all `x86_64-linux` derivations build on real Linux
storage instead of through Determinate Nix's native VM (which trips Apple's
VirtioFS permission semantics).

## Rationale

Determinate Nix's native Linux builder on macOS uses Apple's
`Virtualization.framework` + VirtioFS to run a Linux VM. That VM is broken in
a specific way: `cp --no-preserve=mode` fails with `Permission denied` because
VirtioFS enforces host UID semantics across the guest/host boundary. This is
upstream issue [DeterminateSystems/nix-src#421][issue-421], confirmed by a
Determinate Systems engineer to be unfixable in their builder — the bug has
to be patched in *every* derivation that uses `cp --no-preserve=mode`.

The NixOS Caddy module is one such derivation (`Caddyfile-formatted`). Today
we work around it via `services.caddy.configFile = pkgs.writeText "..." ...`
which sidesteps the formatter entirely. That's a workaround, not a fix, and:

- It loses the build-time validation, per-vhost access logs, and other
  conveniences of the native `services.caddy.virtualHosts` API.
- It will recur with every other derivation in nixpkgs that hits the same
  pattern (and there are many — anything that copies a file from the store
  into `$out` to mutate it tends to use `cp --no-preserve=mode`).
- `deploy-rs.remoteBuild = true` doesn't fix it because flake checks evaluate
  on the controller *before* deploy-rs hands off, so checks still hit the bug.

Routing builds to a real Linux machine bypasses VirtioFS entirely. The
nixos-ct LXC is already part of the homelab, on the same LAN, and has CPU
budget to spare for occasional builds. It's also the standard NixOS pattern
for build farms — a recognizable industry shape worth learning.

[issue-421]: https://github.com/DeterminateSystems/nix-src/issues/421

## Goals

1. All `x86_64-linux` Nix builds initiated from the Mac (interactive
   `nix build`, `nix flake check`, `deploy-rs` flows) run on nixos-ct.
2. Switch the Caddy module back to native `services.caddy.virtualHosts` once
   the builder is in place, dropping the configFile workaround.
3. Match conventional NixOS remote-builder patterns so the setup is portable
   to a dedicated build host later if contention becomes an issue.

## Non-goals

- Building `nixos-test` integration tests. Those require KVM nesting which
  unprivileged LXC doesn't expose. Not currently in use; revisit only if
  needed.
- Migrating off Determinate Nix on the Mac. The Mac stays on Determinate Nix
  for its FlakeHub cache integration; we only change *where* Linux
  derivations build.
- Hardware acceleration (GPU/AVX) for builds. Not relevant for current
  workloads.

## Architecture

```
   Mac (controller)                       nixos-ct (LXC on Proxmox)
   ┌────────────────────┐                 ┌───────────────────────────┐
   │ nix evaluate       │                 │                           │
   │ ┌────────────────┐ │                 │                           │
   │ │ nix-daemon     │─┼─ ssh-ng:// ────►│ nix-daemon (builds)       │
   │ │ (orchestrator) │ │   (build user)  │                           │
   │ └────────────────┘ │◄── store paths ─┤                           │
   │                    │                 │                           │
   │ deploy-rs          │─ ssh:// ───────►│ activation (root)         │
   │                    │   (root)        │                           │
   └────────────────────┘                 └───────────────────────────┘
```

- Mac evaluates flakes locally (cheap; no Linux host required).
- When a Linux derivation needs to build, the Mac's nix-daemon forwards it
  to nixos-ct over SSH using the `ssh-ng://` protocol.
- Build outputs come back to the Mac as paths in `/nix/store`. Since
  derivations are content-addressed, the paths are identical to what
  nixos-ct already has locally.
- When deploy-rs subsequently activates the new system, it `nix copy`s the
  closure to nixos-ct — but every path is already there, so the copy is a
  no-op. Only the activation step does real work.

## Implementation

### Stage 1 — NixOS-side: builder user on nixos-ct

Add a `homelab.nixBuilder` module (or inline into nixos-ct's host config —
single host, single use, probably not worth abstracting yet).

```nix
# Nix/modules/nix-builder.nix (new)
{ config, lib, pkgs, ... }:
let
  cfg = config.homelab.nixBuilder;
in
{
  options.homelab.nixBuilder = {
    enable = lib.mkEnableOption "Accept remote-builder SSH connections from the controller";
    authorizedKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "SSH public keys allowed to dispatch builds.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.nix-builder = {
      isNormalUser = true;
      description = "Nix remote-builder principal";
      openssh.authorizedKeys.keys = cfg.authorizedKeys;
      shell = pkgs.bashInteractive; # required for nix-store --serve over SSH
    };

    nix.settings.trusted-users = [ "nix-builder" ];
  };
}
```

Wire it into `Nix/hosts/nixos-ct/default.nix`:

```nix
homelab.nixBuilder = {
  enable = true;
  authorizedKeys = [
    # Public key of the dedicated builder identity on the Mac.
    # Generate with: ssh-keygen -t ed25519 -f ~/.ssh/nix_builder_ed25519 -C "nix-builder@<mac-hostname>"
    "ssh-ed25519 AAAA... nix-builder@<mac-hostname>"
  ];
};
```

The public key is a *public* key — fine to commit. The private key stays on
the Mac.

### Stage 2 — Bootstrap deploy

Deploy nixos-ct using the *current* (broken-but-working-with-workaround) path
one last time. This installs the `nix-builder` user on the LXC.

```nu
just nix-deploy
```

Verify:

```nu
ssh nix-builder@nixos-ct "nix store ping"
# expect: Store URL: daemon
```

### Stage 3 — Mac-side: nix.conf

Determinate Nix uses two config files: `/etc/nix/nix.conf` (Determinate-managed,
don't touch) and `/etc/nix/nix.custom.conf` (user-managed, persistent across
upgrades).

Add to `/etc/nix/nix.custom.conf`:

```ini
# Route x86_64-linux builds to nixos-ct.
# Format: ssh-ng://USER@HOST SYSTEM SSHKEY MAX-JOBS SPEED-FACTOR FEATURES MANDATORY-FEATURES
builders = ssh-ng://nix-builder@nixos-ct x86_64-linux /Users/murtadha/.ssh/nix_builder_ed25519 8 1 big-parallel,benchmark - -

# Let the builder pull from cache.nixos.org directly instead of routing
# every fetched dep through the Mac.
builders-use-substitutes = true
```

Decision point: the existing line

```
external-builders = [{"args":["builder"],"program":"/usr/local/bin/determinate-nixd","systems":["aarch64-linux","x86_64-linux"]}]
```

…should be **removed**. With two builders configured for the same system,
behavior depends on Nix's internal preference order, which is a debugging
trap. Force everything through nixos-ct; if it's offline, the build fails
loudly instead of silently falling back to the broken VM.

If you want a fallback mechanism later, set up a *second* SSH builder
(another LXC, a Pi, etc.) and let Nix round-robin via the standard
`builders` mechanism. Don't mix `external-builders` with `builders`.

After editing, signal nix-daemon:

```nu
sudo launchctl kickstart -k system/org.nixos.nix-daemon
```

### Stage 4 — Validation

Verify the SSH path:

```nu
nix store ping --store ssh-ng://nix-builder@nixos-ct
# expect: a clean response, no errors
```

Verify a build is actually being remoted (any non-trivial derivation):

```nu
nix build --print-build-logs nixpkgs#hello
# expect: build logs show 'building on ssh-ng://nix-builder@nixos-ct'
```

Then revert the Caddy module workaround. The full revert is:

- Replace `caddyfile = pkgs.writeText ...` and `services.caddy.configFile = caddyfile;`
  with the `services.caddy.virtualHosts = ...` form (using `mkHttpVHost` /
  `mkHttpsVHost` builders against `services` list).
- Drop the explanatory comment block about the Determinate issue.
- Delete the now-unused `mkHttpBlock` / `mkHttpsBlock` helpers.

The earlier-written virtualHosts version (in git history of caddy.nix on
this branch) is the target shape.

Run `just nix-deploy`. Flake check should now pass; activation should
succeed; per-vhost access logs should appear under `/var/log/caddy/access-*.log`.

## Considerations

### Build-time contention with running services

nixos-ct already runs Jellyfin, Sonarr, qBittorrent, etc. A big NixOS rebuild
will spike CPU and RAM. Two mitigations if it becomes a problem:

- Cap parallelism: drop `MAX-JOBS` in the builder line from `8` to `2`.
- Spin up a dedicated builder LXC. Pure NixOS minimal, no services. ~20 lines
  of Terraform (clone the existing LXC config, change name/IP, drop the
  module imports).

Don't preemptively switch to a dedicated builder — the homelab is for
learning, and the contention story is part of the lesson. Live with it for
a few weeks first.

### Trust boundary

`nix-builder` is a `trusted-user` in `nix.settings`, which means anyone able
to authenticate as that user can do anything `nix-daemon` can — including
building derivations that fetch arbitrary code and execute it inside the
build sandbox. Practically equivalent to root on nixos-ct.

The dedicated SSH key for `nix-builder` should:

- Live only on the Mac (not in any backup that leaves the host without
  encryption).
- Not be reused for other purposes.
- Be rotatable: regenerate, push the new pubkey via NixOS deploy, retire
  the old one. Rotation cost is low.

This is no worse than the current state (root SSH from the Mac to
nixos-ct), but it's a separate principal worth understanding.

### Closure transfer over LAN

`builders-use-substitutes = true` is important: without it, every
nixpkgs-cached path the builder needs would route Mac → cache.nixos.org →
Mac → nixos-ct. With it, the builder pulls directly. On a wired LAN the
difference is small; on Wi-Fi from the Mac, large.

### LXC limitations

Unprivileged Proxmox LXC works fine for normal Nix builds (uses Linux user
namespaces, which the LXC already nests). What it *doesn't* support:

- KVM nesting → no `nixos-test` derivations (VM-based integration tests).
- `binfmt_misc` registration → no cross-arch emulation builds for ARM/etc.
  unless we register a binfmt handler at the host level.

Both are acceptable losses for this stage.

### Bootstrap chicken-and-egg

The first deploy that *adds* the `nix-builder` user must use the old
build path (Determinate's native builder, with the Caddy workaround in
place). After that one deploy, the LXC has the user; subsequent deploys
can flow through the new builder.

If something corrupts the `nix-builder` user (e.g., a misapplied NixOS
generation removes them), you'd be unable to deploy via the new path. Two
fallbacks:

1. Roll back nixos-ct's profile via SSH as root (deploy-rs's auto-rollback
   should cover this on a failed deploy, but only if the activation itself
   fails — not if activation succeeds but breaks the user later).
2. Temporarily swap `nix.custom.conf` back to `external-builders` for one
   deploy.

### Why not just use the upstream NixOS module's `nix.buildMachines`?

NixOS supports declaring remote builders *on the Linux side* via
`nix.buildMachines`. That's for when a Linux NixOS machine wants to dispatch
to other builders. Here, the controller is macOS, which has no NixOS module
system — so the Mac-side config has to live in `nix.conf` directly. The
LXC side just needs to *accept* connections (the user + trusted-user bits
above).

If we ever flip the topology (Linux controller, dispatching to Mac for
darwin builds, or to multiple Linux builders), `nix.buildMachines` becomes
the right abstraction on the Linux side.

## Reverting

If the remote-builder path turns out to be net negative (too slow, too
fragile, contention with services unbearable):

1. Re-add `external-builders = ...` to `/etc/nix/nix.custom.conf`.
2. Remove the `builders = ` line.
3. `launchctl kickstart -k system/org.nixos.nix-daemon`.
4. Re-introduce the Caddy `configFile` workaround (or whatever workaround
   the bug-of-the-week needs).

The `homelab.nixBuilder` module on nixos-ct can stay enabled — it's
inert if the Mac isn't dispatching to it. Or `enable = false;` and
redeploy if you want a clean slate.
