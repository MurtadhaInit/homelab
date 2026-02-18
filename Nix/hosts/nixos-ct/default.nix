{ modulesPath, ... }:

{
  imports = [
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
    ../../modules/base.nix

    ../../modules/qbittorrent.nix
  ];

  system.stateVersion = "25.11";
  networking.hostName = "nixos-ct";

  homelab.qbittorrent.enable = true;
}
