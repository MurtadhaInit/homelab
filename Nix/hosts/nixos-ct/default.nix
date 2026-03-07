{ modulesPath, config, ... }:

{
  imports = [
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
    ../../modules/base.nix

    ../../modules/qbittorrent.nix
    ../../modules/jellyfin.nix
    ../../modules/syncthing.nix
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

  # Shared service user — matches the `murtadha` user (UID 1000) on the
  # Proxmox host so bind-mounted files are directly accessible.
  users.users.murtadha = {
    uid = 1000;
    group = "murtadha";
    isSystemUser = true;
  };
  users.groups.murtadha = {
    gid = 1000;
  };

  age.secrets.syncthing-gui-password = {
    file = ../../secrets/syncthing-gui-password.age;
    owner = "murtadha";
  };

  homelab.qbittorrent.enable = true;
  homelab.jellyfin.enable = true;
  homelab.syncthing = {
    enable = true;
    guiPasswordFile = config.age.secrets.syncthing-gui-password.path;
  };
}
