{
  config,
  lib,
  ...
}:

let
  cfg = config.homelab.tailscale;
in
{
  options.homelab.tailscale = {
    enable = lib.mkEnableOption "Tailscale node with homelab defaults (subnet router + DNS reachable over the tailnet)";
    authKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to a file containing a Tailscale auth key for unattended login.
        When null, authenticate once interactively with `tailscale up`.
      '';
    };
    advertiseRoutes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "10.20.30.0/24" ];
      description = ''
        CIDRs to advertise as a subnet router so tailnet peers can reach LAN
        hosts (e.g. the k8s Gateway LoadBalancer at 10.20.30.80). Routes must
        also be approved in the Tailscale admin console.
      '';
    };
    acceptDns = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether this node accepts MagicDNS/split-DNS pushed from the tailnet.
        Keep false on the node that *is* your DNS server, so it keeps using its
        own AdGuard resolver config.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.tailscale = {
      enable = true;
      authKeyFile = cfg.authKeyFile;
      # "server" enables IPv4/IPv6 forwarding sysctls required for subnet routing.
      useRoutingFeatures = "server";
      # Apply these via `tailscale set` (the tailscaled-set unit re-runs it on every
      # activation) rather than `tailscale up`. extraUpFlags only fire at first auth
      # via tailscaled-autoconnect and are skipped once the node is Running, so route
      # or DNS edits made here would otherwise silently never take effect on rebuild.
      # Both flags are emitted unconditionally: an omitted flag leaves tailscaled's
      # persisted pref as-is, so clearing routes has to be stated explicitly (an
      # empty --advertise-routes clears them).
      extraSetFlags = [
        "--advertise-routes=${lib.concatStringsSep "," cfg.advertiseRoutes}"
        "--accept-dns=${lib.boolToString cfg.acceptDns}"
      ];
    };

    # Trust the tailnet interface so peers can reach this host's services
    # (AdGuard DNS, the *arr web UIs, etc.) without per-port firewall rules.
    # The tailnet is private and authenticated, so this is the intended exposure.
    networking.firewall.trustedInterfaces = [ config.services.tailscale.interfaceName ];
  };
}
