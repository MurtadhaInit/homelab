# Run-once per Mac, and only on macOS + Determinate Nix.
# Registering the host as a builder makes *every* x86_64-linux build offload
# there, not just `nix-deploy`, which sidesteps Determinate's external builder
# (and its bugs) entirely: with `builders` set, Nix tries SSH first and only falls
# back to it. The daemon runs under launchd with no tty and no ssh-agent, so it
# needs its own passphrase-less key, owned by and readable only to root. Settings
# go in nix.custom.conf because Determinate replaces nix.conf on upgrade, and
# they land after its `!include`, so they win. The target host must authorize the
# printed pubkey (`users.users.nix-builder` in the host's default.nix).

# Register a NixOS host as this Mac's remote builder (assuming a Determinate Nix distro)
[group('nix')]
[macos]
[working-directory('Nix')]
nix-remote-builder host="10.20.30.50" user="nix-builder" jobs="2":
    #!/usr/bin/env bash
    set -euo pipefail
    key=/var/root/.ssh/nix-builder
    conf=/etc/nix/nix.custom.conf

    if ! sudo test -f "$key"; then
        sudo mkdir -p /var/root/.ssh
        sudo ssh-keygen -t ed25519 -N "" -C nix-remote-builder -f "$key"
    fi

    # Field 8 of the machines spec is the base64 of the host's *public key line*,
    # which Nix decodes into a throwaway known_hosts — no agent, no prompt.
    hostkey=$(ssh-keyscan -t ed25519 {{ host }} 2>/dev/null | awk '/ ssh-ed25519 /{print $2, $3; exit}' | base64 | tr -d '\n')
    [ -n "$hostkey" ] || { echo "no ed25519 host key from {{ host }}" >&2; exit 1; }

    # `jobs` caps what *this Mac* dispatches concurrently; keep it in step with the
    # target's own nix.settings.max-jobs so RAM there stays within budget.
    sudo sed -i '' '/^builders/d' "$conf"
    printf 'builders-use-substitutes = true\nbuilders = ssh-ng://%s@%s x86_64-linux %s %s 1 big-parallel - %s\n' \
        '{{ user }}' '{{ host }}' "$key" '{{ jobs }}' "$hostkey" | sudo tee -a "$conf" >/dev/null
    sudo launchctl kickstart -k system/systems.determinate.nix-daemon

    # Probe by actually building something, since an SSH check would still pass
    # while Nix silently falls back to the external builder.
    # Seeded from the shell's PID so every run is a distinct derivation that has
    # to be built; a fixed one would go green off the local store without the
    # builder being involved at all.
    # The hyphen in the env var name is a canary: Determinate's external builder
    # assigns the environment through a shell, where `hyphen-env=...` parses as a
    # command rather than an assignment (i.e. fails).
    probe='let pkgs = (builtins.getFlake (toString ./.)).inputs.nixpkgs.legacyPackages.x86_64-linux;
           in pkgs.runCommand "remote-builder-probe" { "hyphen-env" = builtins.getEnv "PROBE_SEED"; } "echo ok > $out"'
    echo
    if PROBE_SEED=$$ nix build --impure --no-link --no-substitute --expr "$probe" >/dev/null 2>&1; then
        echo "✅ x86_64-linux builds are routing to {{ user }}@{{ host }}."
    else
        echo "⚠️  Build did not route to {{ user }}@{{ host }}. If the host didn't"
        echo "    authorise this key yet, add it and deploy, then re-run:"
        sudo cat "${key}.pub"
    fi
