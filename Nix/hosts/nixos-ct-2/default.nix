# Small redundant DNS and Tailscale subnet router on `prox2` for failover (e.g. if `prox` fails).
{ modulesPath, config, ... }:

{
  imports = [
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
    ../../modules/base.nix

    ../../modules/adguardhome.nix
    ../../modules/tailscale.nix
  ];

  # ONLY bump up on fresh installs!
  system.stateVersion = "26.11";

  proxmoxLXC = {
    manageNetwork = false; # Proxmox manages network via initialization.ip_config
    manageHostName = false; # Proxmox manages hostname via initialization.hostname
    privileged = false;
  };

  # Don't stall boot waiting for network-online.target
  systemd.network.wait-online.enable = false;

  # Let the Proxmox host handle TRIM for the underlying storage
  services.fstrim.enable = false;

  age.secrets.tailscale-oauth-secret.file = ../../secrets/tailscale-oauth-secret.age;

  homelab.adguardhome.enable = true;
  homelab.tailscale = {
    enable = true;
    # Same prefix as `nixos-ct`: Tailscale only fails over between routers advertising
    # an identical route, and keeps the older one as primary.
    advertiseRoutes = [ "10.20.30.0/24" ];
    acceptDns = false;
    advertiseTags = [ "tag:subnet-router" ];
    authKeyFile = config.age.secrets.tailscale-oauth-secret.path;
  };
}
