let
  # Get with: ssh-keyscan <IP_ADDRESS> | grep ed25519
  nixos-ct = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMdw4wgxlGGzgOmHrZEp0sqAwma44dWlGzw6/xySLhiJ";
  # murtadha = "";
in
{
  # Edit with (in this dir): nix run github:ryantm/agenix -- -e <filename>.age
  # Re-encrypt from a file (Nushell): open <filename.key> | nix run github:ryantm/agenix -- -e <filename>.age

  "syncthing-gui-password.age".publicKeys = [ nixos-ct ];
  # Generate with: openssl rand -hex 32 | nix run github:ryantm/agenix -- -e grafana-secret-key.age
  "grafana-secret-key.age".publicKeys = [ nixos-ct ];
  "grafana-admin-password.age".publicKeys = [ nixos-ct ];
  # Generate a key pair with: nix run nixpkgs#syncthing -- generate --config ./conf --data ./data
  # Then (Nushell): open ./conf/cert.pem | nix run github:ryantm/agenix -- -e syncthing-cert.age
  # And: open ./conf/key.pem | nix run github:ryantm/agenix -- -e syncthing-key.age
  # Obtain device ID with: nix run nixpkgs#syncthing -- device-id --config ./conf --data ./data
  "syncthing-key.age".publicKeys = [ nixos-ct ];
  "syncthing-cert.age".publicKeys = [ nixos-ct ];
}
