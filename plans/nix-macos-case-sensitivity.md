# Deploying NixOS from macOS: the case-insensitive `/nix` problem

**Status:** known issue, worked around. The root fix is deferred -- see
[The real fix](#the-real-fix-deferred) when there is an afternoon to spare.

## Symptom

`TERM=xterm-ghostty` failed to resolve on `nixos-ct` even though
`ghostty.terminfo` was in `environment.systemPackages` and the store path was
present on the host:

```
[root@nixos-ct:~]# systemctl status syncthing.service
'xterm-ghostty': unknown terminal type.
```

Inside `tmux` everything worked, which made it look like a Ghostty problem.

## Root cause

macOS mounts the Nix store on a **case-insensitive** APFS volume:

```
$ diskutil apfs list | grep "Nix Store"
Name: Nix Store (Case-insensitive)
```

ncurses ships terminfo directories whose names differ only by case --
`a/A`, `e/E`, `l/L`, `m/M`, `n/N`, `p/P`, `q/Q`, `x/X`. These cannot coexist on
a case-insensitive filesystem, so Nix applies its **case hack**, renaming one of
each pair on disk to `<letter>~nix~case~hack~1`.

`buildEnv` (which produces `system-path`) then reads those on-disk names and
bakes them **literally into its symlink targets**. On the target's
case-sensitive ext4 those names do not exist, so the links dangle:

```
/run/current-system/sw/share/terminfo/x -> .../ncurses-6.6/share/terminfo/x~nix~case~hack~1
```

`buildEnv` warns about this at build time rather than failing, so it went
unnoticed. The warnings are in the build log on the Mac:

```
$ nix log /nix/store/...-system-path | grep -c "dangling symlink"
3
```

### Why it looked like a Ghostty bug

- `xterm-ghostty` lives in `terminfo/x/` -- destroyed.
- `ghostty` lives in `terminfo/g/`, and `g` has **no case twin**, so it merged
  correctly and resolved fine.
- `tmux-256color` lives in `terminfo/t/`; `t` has no case twin either. That is
  the only reason tmux sessions worked -- an accident of first letter, not a
  tmux feature.
- `xterm-256color` resolved via ncurses' own store path, which is second in
  `infocmp -D`'s search path, bypassing `system-path` entirely.

This is **not** terminfo-specific. Any two packages merged into `system-path`
whose filenames differ only by case are affected.

## Not caused by Determinate Nix

All three macOS installers default to a case-insensitive volume, so switching
Nix distributions does not help:

| Installer | Default | Override |
| --- | --- | --- |
| Determinate `nix-installer` | `case_sensitive: false` (macOS planner default; CLI arg `default_value = "false"`) | `--case-sensitive` / `NIX_INSTALLER_CASE_SENSITIVE=true` |
| Upstream `create-darwin-volume.sh` | `NIX_VOLUME_FS="${NIX_VOLUME_FS:-APFS}"` | `NIX_VOLUME_FS="Case-sensitive APFS"` |
| `lix-installer` | fork of Determinate's installer, same default | same flag |

Upstream issue arguing the installer should just create a case-sensitive
volume: <https://github.com/NixOS/nix/issues/10746> (open).

## Current workaround

Both live in the `justfile`, which has `[macos]` and `[linux]` variants of the
`nix-deploy` recipe. The macOS one passes:

- `--remote-build`, so `deploy-rs` builds on the target's case-sensitive store.
- `--skip-checks`, because `deploy-rs` runs `nix flake check` before deploying
  and that **builds the NixOS toplevel locally**, which cannot succeed here.

The Linux variant passes neither: an `x86_64-linux` desktop builds `nixos-ct`
natively on a case-sensitive store, which is both correct and faster than the
LXC's CPU for anything not already in the binary cache.

### Why the gate is not in the flake

`deploy.nodes.<host>.remoteBuild = true` would be the obvious place, but a flake
cannot know which platform it is being deployed *from* -- `builtins.currentSystem`
is unavailable under pure evaluation. And the setting cannot be overridden back
off, because deploy-rs's CLI flag is purely additive (`src/lib.rs`):

```rust
// build all machines remotely when the command line flag is set
if cmd_overrides.remote_build {
    merged_settings.remote_build = Some(cmd_overrides.remote_build);
}
```

So `remoteBuild = true` in the flake would force remote builds everywhere,
including from the desktop. Passing the flag per-platform from the `justfile` is
the only way to gate it.

**Footgun:** invoking `nix run github:serokell/deploy-rs .` directly from macOS,
bypassing `just`, will now attempt a local build and fail. That failure is loud
(`buildEnv error: cannot create directory .../terminfo/x`), not the silent
corruption this whole document is about, so it is an acceptable trade.

### What skipping the checks actually costs

Less than it sounds, because `remoteBuild` already moved the build to the target:

- **Build failures** still block the deploy -- they surface during the remote
  build, and `deploy-rs` will not activate a profile that failed to build.
- **Evaluation errors** still surface: `deploy-rs` has to evaluate the flake to
  find the profile path.
- **`magic-rollback` / `auto-rollback`** remain as the real safety net for a bad
  activation.
- **Genuinely lost:** `deploy-schema`, which validates the `deploy` attrset
  against a JSON schema and would catch a malformed or typo'd `deploy.nodes`
  entry. It cannot be run standalone as a substitute -- it transitively depends
  on the activation package, so it fails on macOS for the same reason.

Deploying from a Linux host runs the full checks (that is the `[linux]` recipe).

## The real fix (deferred)

Two knobs are required, not one -- a case-sensitive volume alone is not enough,
because `use-case-hack` is gated on **platform, not filesystem**
(<https://github.com/NixOS/nix/issues/2064>):

```
$ nix config show --json | jq '."use-case-hack"'
{ "defaultValue": true, "value": true,
  "description": "Whether to enable a macOS-specific hack for dealing with file name case collisions." }
```

Migration (destructive -- wipes the store; everything is re-substitutable and
pinned by `flake.lock`, and `~/.dotfiles` / `~/.ssh` are untouched):

```sh
sudo /nix/nix-installer uninstall
curl -fsSL https://install.determinate.systems/nix | sh -s -- install macos --case-sensitive --determinate
printf 'use-case-hack = false\n' | sudo tee -a /etc/nix/nix.custom.conf
home-manager switch --flake ~/.dotfiles#<config>
```

Keep a non-Nix shell open during the migration: home-manager's symlinks dangle
until the last step. The login shell is Homebrew's `nu`, so it survives.

### Acceptance test

```sh
diskutil info /nix | grep -i "File System Personality"   # -> Case-sensitive APFS
nix config show | grep case-hack                         # -> use-case-hack = false

cd Nix
nix build --no-link .#nixosConfigurations.nixos-ct.config.system.build.toplevel
nix flake check .
```

Both currently fail on macOS. When they pass, collapse the `justfile`'s two
`nix-deploy` variants back into one plain recipe: the Mac would then build
`x86_64-linux` correctly through the builder VM, so neither `--remote-build` nor
`--skip-checks` is needed. Keeping `--remote-build` on macOS would still be a
reasonable preference (it avoids the VM round-trip), but it stops being a
workaround.

## Verifying the terminfo state on a host

```sh
# every former case-twin letter must be OK
ssh nixos-ct 'for d in a e l m n p q x; do printf "%s: " $d; \
  ls /run/current-system/sw/share/terminfo/$d/ >/dev/null 2>&1 && echo OK || echo DANGLING; done'

# must be a real directory, not a symlink ending in ~nix~case~hack~N
ssh nixos-ct 'ls -ld /run/current-system/sw/share/terminfo/x'

# resolve from the system path alone -- HOME must be neutralised, since a
# client-installed ~/.terminfo copy would otherwise mask the result
ssh nixos-ct 'env -u TERMINFO HOME=/var/empty infocmp -x xterm-ghostty >/dev/null && echo ok'

# a correct build emits zero of these
ssh nixos-ct 'nix log /run/current-system/sw | grep -c "dangling symlink"'
```

## Related: Ghostty's `ssh-terminfo` cache

`~/.dotfiles/Applications/ghostty/config` sets
`shell-integration-features = ssh-env, ssh-terminfo`, which installs Ghostty's
terminfo into the remote user's `~/.terminfo` on first connect and **caches the
success per host**. That cache is never re-validated, so it can assert an
install that a later host rebuild removed:

```sh
ghostty +ssh-cache                                  # list
ghostty +ssh-cache --remove=root@10.20.30.50        # force a re-probe
```

With `enableAllTerminfo` on the NixOS hosts this integration is a no-op for them
(its probe's first line, `infocmp xterm-ghostty && exit 0`, now succeeds against
the system path). It stays useful for the Proxmox hosts and Ubuntu VM, which Nix
does not manage.
