{ modulesPath, ... }:

{
  imports = [
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
    ../../modules/base.nix

    ../../modules/qbittorrent.nix
    ../../modules/jellyfin.nix
  ];

  system.stateVersion = "25.11";

  proxmoxLXC = {
    manageNetwork = false; # Proxmox manages network via initialization.ip_config
    manageHostName = false; # Proxmox manages hostname via initialization.hostname
    privileged = true;
  };

  # Don't stall boot waiting for network-online.target
  systemd.network.wait-online.enable = false;

  # Let the Proxmox host handle TRIM for the underlying storage
  services.fstrim.enable = false;

  homelab.qbittorrent.enable = true;
  homelab.jellyfin.enable = true;
}
