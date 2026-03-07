let
  # Get with: ssh-keyscan <IP_ADDRESS> | grep ed25519
  nixos-ct = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMdw4wgxlGGzgOmHrZEp0sqAwma44dWlGzw6/xySLhiJ";
  # murtadha = "";
in
{
  # Edit with (in this dir): nix run github:ryantm/agenix -- -e syncthing-gui-password.age
  "syncthing-gui-password.age".publicKeys = [ nixos-ct ];
}
