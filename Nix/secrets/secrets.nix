let
  # Get with: ssh-keyscan <IP_ADDRESS> | grep ed25519
  nixos-ct = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMdw4wgxlGGzgOmHrZEp0sqAwma44dWlGzw6/xySLhiJ";
  # Get with: age-keygen -y ~/.ssh/keys/age.txt
  murtadha = "age1fjfzlw6ah4k3kh07ray363e87rt6z8rfhljjxprwhqa7y0pw9vjqvv0f9h";
in
{
  # NOTE: Edit with (in this dir): nix run github:ryantm/agenix -- -e <filename>.age
  # Re-encrypt from a file (Nushell): open <filename.key> | nix run github:ryantm/agenix -- -e <filename>.age
  # Re-key (re-encrypt) all secrets:
  # You need a private key (identity) to first decrypt the secrets (either one works, or specify both)
  # E.g. to temporarily get the nixos-ct private key: scp root@10.20.30.50:/etc/ssh/ssh_host_ed25519_key /tmp/nixos-ct-key
  # E.g. to specify both keys: nix run github:ryantm/agenix -- -r -i ~/.ssh/keys/age.txt -i /tmp/nixos-ct-key
  # Remove the copied private key afterwards: rm /tmp/nixos-ct-key

  "syncthing-gui-password.age".publicKeys = [
    nixos-ct
    murtadha
  ];
  # Generate a key pair with: nix run nixpkgs#syncthing -- generate --config ./conf --data ./data
  # Then (Nushell): open ./conf/cert.pem | nix run github:ryantm/agenix -- -e syncthing-cert.age
  # And: open ./conf/key.pem | nix run github:ryantm/agenix -- -e syncthing-key.age
  # Obtain device ID with: nix run nixpkgs#syncthing -- device-id --config ./conf --data ./data
  "syncthing-key.age".publicKeys = [ nixos-ct ];
  "syncthing-cert.age".publicKeys = [ nixos-ct ];

  "grafana-admin-password.age".publicKeys = [
    nixos-ct
    murtadha
  ];
  # Generate with: openssl rand -hex 32 | nix run github:ryantm/agenix -- -e grafana-secret-key.age
  "grafana-secret-key.age".publicKeys = [ nixos-ct ];

  # Cloudflare API token for Caddy DNS-01 ACME challenges. Required perms: Zone.Zone:Read, Zone.DNS:Edit
  # Create with: "CF_API_TOKEN=<token>" | nix run github:ryantm/agenix -- -e caddy-cloudflare-token.age
  "caddy-cloudflare-token.age".publicKeys = [
    nixos-ct
    murtadha
  ];

  # Generate with (Nushell): $"PROWLARR__AUTH__APIKEY=(openssl rand -hex 16 | str trim)\n" | nix run github:ryantm/agenix -- -e prowlarr-api-key.age
  "prowlarr-api-key.age".publicKeys = [ nixos-ct ];

  # Generate with (Nushell): $"SONARR__AUTH__APIKEY=(openssl rand -hex 16 | str trim)\n" | nix run github:ryantm/agenix -- -e sonarr-api-key.age
  "sonarr-api-key.age".publicKeys = [ nixos-ct ];

  # SABnzbd login and API secrets (INI format, generate in Nushell):
  # let api_key = (openssl rand -hex 16 | str trim)
  # let nzb_key = (openssl rand -hex 16 | str trim)
  # $"[misc]\napi_key = ($api_key)\nnzb_key = ($nzb_key)\nusername = murtadha\npassword = <your-password>\n" | nix run github:ryantm/agenix -- -e sabnzbd-secrets.age
  # NOTE: avoid special characters in the password
  "sabnzbd-secrets.age".publicKeys = [
    nixos-ct
    murtadha
  ];
  # SABnzbd Usenet server (provider) config and credentials (INI format)
  "sabnzbd-server.age".publicKeys = [
    nixos-ct
    murtadha
  ];
}
