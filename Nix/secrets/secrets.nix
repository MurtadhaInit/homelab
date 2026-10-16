let
  # Get with: ssh-keyscan <IP_ADDRESS> | grep ed25519
  nixos-ct = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMdw4wgxlGGzgOmHrZEp0sqAwma44dWlGzw6/xySLhiJ";
  nixos-ct-2 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINxYA/fuLFoc7m8wV+fwh40SB9/UjL8ih1FBHhNJKljS";
  # Generate a new key pair with: age-keygen -o ~/.ssh/keys/age.txt
  # Then print the public key (to paste here) with: age-keygen -y ~/.ssh/keys/age.txt
  murtadha = "age1fjfzlw6ah4k3kh07ray363e87rt6z8rfhljjxprwhqa7y0pw9vjqvv0f9h";
in
{
  # NOTE: Edit with (in this dir): nix run github:ryantm/agenix -- -e <filename>.age
  # Re-encrypt from a file (Nushell): open <filename.key> | nix run github:ryantm/agenix -- -e <filename>.age
  # Every secret is also encrypted to `murtadha`, so that key alone can decrypt any of them.
  # Re-key (re-encrypt) all secrets, e.g. after changing recipients:
  # nix run github:ryantm/agenix -- -r -i ~/.ssh/keys/age.txt

  "syncthing-gui-password.age".publicKeys = [
    murtadha
    nixos-ct
  ];
  # Generate a key pair with: nix run nixpkgs#syncthing -- generate --config ./conf --data ./data
  # Then (Nushell): open ./conf/cert.pem | nix run github:ryantm/agenix -- -e syncthing-cert.age
  # And: open ./conf/key.pem | nix run github:ryantm/agenix -- -e syncthing-key.age
  # Obtain device ID with: nix run nixpkgs#syncthing -- device-id --config ./conf --data ./data
  "syncthing-key.age".publicKeys = [
    murtadha
    nixos-ct
  ];
  "syncthing-cert.age".publicKeys = [
    murtadha
    nixos-ct
  ];

  # Cloudflare API token for Caddy DNS-01 ACME challenges. Required perms: Zone.Zone:Read, Zone.DNS:Edit
  # Create with: "CF_API_TOKEN=<token>" | nix run github:ryantm/agenix -- -e caddy-cloudflare-token.age
  "caddy-cloudflare-token.age".publicKeys = [
    murtadha
    nixos-ct
  ];

  # Generate with (Nushell): $"PROWLARR__AUTH__APIKEY=(openssl rand -hex 16 | str trim)\n" | nix run github:ryantm/agenix -- -e prowlarr-api-key.age
  "prowlarr-api-key.age".publicKeys = [
    murtadha
    nixos-ct
  ];

  # Generate with (Nushell): $"SONARR__AUTH__APIKEY=(openssl rand -hex 16 | str trim)\n" | nix run github:ryantm/agenix -- -e sonarr-api-key.age
  "sonarr-api-key.age".publicKeys = [
    murtadha
    nixos-ct
  ];

  # SABnzbd login and API secrets (INI format, generate in Nushell):
  # let api_key = (openssl rand -hex 16 | str trim)
  # let nzb_key = (openssl rand -hex 16 | str trim)
  # $"[misc]\napi_key = ($api_key)\nnzb_key = ($nzb_key)\nusername = murtadha\npassword = <your-password>\n" | nix run github:ryantm/agenix -- -e sabnzbd-secrets.age
  # NOTE: avoid special characters in the password
  "sabnzbd-secrets.age".publicKeys = [
    murtadha
    nixos-ct
  ];
  # SABnzbd Usenet server (provider) config and credentials (INI format)
  "sabnzbd-server.age".publicKeys = [
    murtadha
    nixos-ct
  ];

  # Tailscale OAuth client secret for unattended login of the subnet routers.
  # Create it in the admin console: Settings -> Trust credentials -> (new) OAuth.
  # Give the token Auth Keys (write) access with the `tag:subnet-router` tag.
  # Then encrypt the client secret with (Nushell):
  # "<tskey-client-...>" | nix run github:ryantm/agenix -- -e tailscale-oauth-secret.age
  "tailscale-oauth-secret.age".publicKeys = [
    murtadha
    nixos-ct
    nixos-ct-2
  ];

  # Stash web UI password (this file must hold the bcrypt *hash*).
  # Create with (Nushell): htpasswd -nbB -C 12 murtadha "<your-password>" | split row ":" | get 1 | str trim | nix run github:ryantm/agenix -- -e stash-password.age
  "stash-password.age".publicKeys = [
    murtadha
    nixos-ct
  ];
  # Stash JWT signing secret. Create with (Nushell):
  # openssl rand -hex 32 | str trim | nix run github:ryantm/agenix -- -e stash-jwt-secret.age
  "stash-jwt-secret.age".publicKeys = [
    murtadha
    nixos-ct
  ];
  # Stash session store secret. Create with (Nushell):
  # openssl rand -hex 32 | str trim | nix run github:ryantm/agenix -- -e stash-session-key.age
  "stash-session-key.age".publicKeys = [
    murtadha
    nixos-ct
  ];
}
