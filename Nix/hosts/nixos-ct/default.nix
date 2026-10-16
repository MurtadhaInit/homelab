{ modulesPath, config, ... }:

{
  imports = [
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
    ../../modules/base.nix

    ../../modules/qbittorrent.nix
    ../../modules/jellyfin.nix
    ../../modules/syncthing.nix
    ../../modules/caddy.nix
    ../../modules/adguardhome.nix
    ../../modules/tailscale.nix
    ../../modules/prowlarr.nix
    ../../modules/sonarr.nix
    ../../modules/sabnzbd.nix
    ../../modules/seerr.nix
  ];

  # ONLY bump up on fresh installs!
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

  # Deploys build on this host, so sizing to this container's limited resources:
  # the default `auto` runs one derivation per core, and that many concurrent
  # compilers can exhaust RAM and take running services with them.
  # NOTE: revisit alongside any change to the LXC's allocation.
  nix.settings.max-jobs = 2;

  # Remote-builder target: a Mac can't build x86_64-linux natively, so its Nix
  # daemon dispatches those builds to this user over SSH.
  # `trusted-users` lets the user push unsigned paths into this host's store.
  # `just nix-remote-builder` generates the key below.
  # The registration of this host as a builder lives in that Mac's nix-darwin config.
  users.users.nix-builder = {
    isNormalUser = true;
    group = "nix-builder";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMUj6S24kuQDE2NgE/ekkA1nq3/3iFUb7SAbTrKClKtA nix-remote-builder"
    ];
  };
  users.groups.nix-builder = { };
  nix.settings.trusted-users = [ "nix-builder" ];

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
    sabnzbd-secrets = {
      file = ../../secrets/sabnzbd-secrets.age;
      owner = "murtadha";
    };
    sabnzbd-server = {
      file = ../../secrets/sabnzbd-server.age;
      owner = "murtadha";
    };
    tailscale-oauth-secret = {
      file = ../../secrets/tailscale-oauth-secret.age;
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
  homelab.caddy = {
    enable = true;
    proxmoxHosts = {
      prox = "10.20.30.40";
      prox2 = "10.20.30.100";
    };
    domain = "home.murtadha.dev";
    cloudflareTokenFile = config.age.secrets.caddy-cloudflare-token.path;
  };
  homelab.adguardhome.enable = true;
  homelab.prowlarr = {
    enable = true;
    apiKeyFile = config.age.secrets.prowlarr-api-key.path;
  };
  homelab.sonarr = {
    enable = true;
    apiKeyFile = config.age.secrets.sonarr-api-key.path;
  };
  homelab.sabnzbd = {
    enable = true;
    secretsFile = config.age.secrets.sabnzbd-secrets.path;
    serverSecretsFile = config.age.secrets.sabnzbd-server.path;
  };
  homelab.seerr.enable = true;
  homelab.tailscale = {
    enable = true;
    advertiseRoutes = [ "10.20.30.0/24" ];
    acceptDns = false;
    advertiseTags = [ "tag:subnet-router" ];
    authKeyFile = config.age.secrets.tailscale-oauth-secret.path;
  };
}
