# A Mac can't natively build the x86_64-linux derivations this repo's NixOS hosts
# (or any other's) are made of, but the Mac's Nix daemon can dispatch them over SSH
# to a NixOS machine on the LAN (a self-hosted remote builder from our own infra).
#
# Three pieces make that work and they live apart:
#   1. The builder's own end: a build user and its authorized key, added to that host's module config here.
#   2. The registration naming it in the Mac's nix-darwin config.
#   3. And the SSH key material below (the only part neither configuration can produce for itself).
#
# That key is passphrase-less and owned by root because the Nix daemon runs under
# launchd: no tty to prompt on and no ssh-agent to borrow an unlocked key from.

# Set up this Mac's remote-builder key and check that Linux builds reach the builder
[group('nix')]
[macos]
[working-directory('Nix')]
nix-remote-builder host="10.20.30.50" user="nix-builder":
    #!/usr/bin/env bash
    set -euo pipefail
    key=/var/root/.ssh/nix-builder

    if ! sudo test -f "$key"; then
        sudo mkdir -p /var/root/.ssh
        sudo ssh-keygen -t ed25519 -N "" -C nix-remote-builder -f "$key"
    fi

    # Nix takes the builder's host key inline as base64 and decodes it into a throwaway
    # known_hosts, so the daemon never consults one of its own or prompts about it.
    hostkey=$(ssh-keyscan -t ed25519 {{ host }} 2>/dev/null | awk '/ ssh-ed25519 /{print $2, $3; exit}' | base64 | tr -d '\n')
    [ -n "$hostkey" ] || { echo "no ed25519 host key from {{ host }}" >&2; exit 1; }

    echo
    echo "→ authorize on {{ host }}, in its host module here:"
    sudo cat "${key}.pub"
    echo "→ record as the build machine's public host key, in the Mac's nix-darwin config:"
    echo "$hostkey"

    # Whether a build actually reached the builder isn't visible from the outside:
    # Determinate Nix also ships a local Linux VM that satisfies x86_64-linux, and Nix
    # falls back to it silently. So the probe is rigged to be answerable only by the
    # real thing — seeded from the shell's PID so each run is a derivation nothing can
    # have cached, and carrying a hyphen in an env var name, which the VM chokes on
    # because it assigns the environment through a shell, where `hyphen-env=...` parses
    # as a command rather than an assignment.
    probe='let pkgs = (builtins.getFlake (toString ./.)).inputs.nixpkgs.legacyPackages.x86_64-linux;
           in pkgs.runCommand "remote-builder-probe" { "hyphen-env" = builtins.getEnv "PROBE_SEED"; } "echo ok > $out"'
    echo
    if PROBE_SEED=$$ nix build --impure --no-link --expr "$probe" >/dev/null 2>&1; then
        echo "✅ x86_64-linux builds are reaching {{ user }}@{{ host }}."
    else
        echo "⚠️  Builds are not reaching {{ user }}@{{ host }}. Put the two values above"
        echo "    in place, deploy this repo, and \`darwin-rebuild switch\` on the Mac."
    fi
