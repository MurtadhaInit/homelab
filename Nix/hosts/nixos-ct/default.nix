{ modulesPath, config, ... }:

{
  imports = [
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
    ../../modules/base.nix

    ../../modules/qbittorrent.nix
    ../../modules/jellyfin.nix
    ../../modules/syncthing.nix
    ../../modules/prometheus.nix
    ../../modules/grafana.nix
    ../../modules/caddy.nix
    ../../modules/adguardhome.nix
    ../../modules/prowlarr.nix
    ../../modules/sonarr.nix
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

  age.secrets = {
    syncthing-gui-password = {
      file = ../../secrets/syncthing-gui-password.age;
      owner = "murtadha";
    };
    grafana-secret-key = {
      file = ../../secrets/grafana-secret-key.age;
      owner = "grafana";
    };
    grafana-admin-password = {
      file = ../../secrets/grafana-admin-password.age;
      owner = "grafana";
    };
    syncthing-key = {
      file = ../../secrets/syncthing-key.age;
      owner = "murtadha";
      mode = "0400";
    };
    syncthing-cert = {
      file = ../../secrets/syncthing-cert.age;
      owner = "murtadha";
      mode = "0444";
    };
    caddy-cloudflare-token = {
      file = ../../secrets/caddy-cloudflare-token.age;
    };
    prowlarr-api-key = {
      file = ../../secrets/prowlarr-api-key.age;
    };
    sonarr-api-key = {
      file = ../../secrets/sonarr-api-key.age;
    };
  };

  homelab.qbittorrent.enable = true;
  homelab.jellyfin.enable = true;
  homelab.syncthing = {
    enable = true;
    guiPasswordFile = config.age.secrets.syncthing-gui-password.path;
    keyFile = config.age.secrets.syncthing-key.path;
    certFile = config.age.secrets.syncthing-cert.path;
  };
  homelab.prometheus = {
    enable = true;
    proxmoxHostAddress = "10.20.30.40";
  };
  homelab.grafana = {
    enable = true;
    secretKeyFile = config.age.secrets.grafana-secret-key.path;
    adminPasswordFile = config.age.secrets.grafana-admin-password.path;
  };
  homelab.caddy = {
    enable = true;
    proxmoxAddress = "10.20.30.40";
    publicDomain = "home.murtadha.dev";
    cloudflareTokenFile = config.age.secrets.caddy-cloudflare-token.path;
  };
  homelab.adguardhome = {
    enable = true;
    publicDomain = "home.murtadha.dev";
  };
  homelab.prowlarr = {
    enable = true;
    apiKeyFile = config.age.secrets.prowlarr-api-key.path;
  };
  homelab.sonarr = {
    enable = true;
    apiKeyFile = config.age.secrets.sonarr-api-key.path;
  };
}
