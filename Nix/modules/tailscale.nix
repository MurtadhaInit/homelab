{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.homelab.tailscale;

  # Emitted unconditionally: an omitted flag leaves tailscaled's persisted pref
  # as-is, so clearing routes has to be stated explicitly (an empty
  # --advertise-routes clears them).
  prefFlags = [
    "--advertise-routes=${lib.concatStringsSep "," cfg.advertiseRoutes}"
    "--accept-dns=${lib.boolToString cfg.acceptDns}"
  ];
in
{
  options.homelab.tailscale = {
    enable = lib.mkEnableOption "Tailscale node with homelab defaults (subnet router + DNS reachable over the tailnet)";
    authKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to a file containing a Tailscale OAuth client secret (`auth_keys`
        scope) for unattended login. Unlike auth keys, it doesn't expire.
        When null, authenticate once interactively with `tailscale up`.
      '';
    };
    advertiseTags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "tag:subnet-router" ];
      description = ''
        Tags the node registers with. Required with an OAuth client secret,
        which can only create keys for the tags it was granted.
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
    assertions = [
      {
        assertion = cfg.authKeyFile == null || cfg.advertiseTags != [ ];
        message = "homelab.tailscale.advertiseTags must be set when logging in with an OAuth client secret.";
      }
    ];

    services.tailscale = {
      enable = true;
      authKeyFile = cfg.authKeyFile;
      # OAuth-minted keys default to ephemeral (node removed once offline) and
      # needing device approval, neither of which suits a long-lived router.
      authKeyParameters = {
        ephemeral = false;
        preauthorized = true;
      };
      # "server" enables IPv4/IPv6 forwarding sysctls required for subnet routing.
      useRoutingFeatures = "server";
      # Prefs are applied via `tailscale set` (the tailscaled-set unit re-runs it on
      # every activation): extraUpFlags only fire at first auth via
      # tailscaled-autoconnect and are skipped once the node is Running, so route or
      # DNS edits would otherwise silently never take effect on rebuild.
      extraSetFlags = prefFlags;
      # `tailscale up` won't log in unless it restates every saved non-default pref
      # (e.g. ones `set` already applied after a failed first login).
      # Tags can only be set at login, so they go here alone.
      extraUpFlags = prefFlags ++ [
        "--advertise-tags=${lib.concatStringsSep "," cfg.advertiseTags}"
      ];
    };

    # Trust the tailnet interface so peers can reach this host's services
    # (AdGuard DNS, the *arr web UIs, etc.) without per-port firewall rules.
    # The tailnet is private and authenticated, so this is the intended exposure.
    networking.firewall.trustedInterfaces = [ config.services.tailscale.interfaceName ];

    # Tailscale's throughput recommendation for subnet routers and exit nodes:
    # without rx-udp-gro-forwarding, UDP packets that get *forwarded* are not
    # candidates for GRO coalescing, which caps throughput through the rest of
    # the stack. Scoped to traffic transiting to *other* LAN hosts; services on
    # this node terminate locally and never take the forwarding path.
    # https://tailscale.com/docs/reference/best-practices/performance
    #
    # tailscaled does not apply this itself outside its container image (where
    # it sits behind TS_EXPERIMENTAL_ENABLE_FORWARDING_OPTIMIZATIONS), so a
    # subnet router has to carry the unit.
    systemd.services.tailscale-udp-gro = lib.mkIf (cfg.advertiseRoutes != [ ]) {
      description = "Enable UDP GRO forwarding on the default-route link for Tailscale";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      before = [ "tailscaled.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # network-online.target has no dependencies when wait-online is disabled, so it
        # can be reached before the default route is installed and the interface lookup
        # finds nothing. Bounded retry keeps the unit correct either way.
        Restart = "on-failure";
        RestartSec = 1;
      };
      unitConfig = {
        StartLimitBurst = 10;
        StartLimitIntervalSec = 30;
      };
      script = ''
        # Not `route show 8.8.8.8`, which is what the Tailscale docs print but
        # actually returns nothing (see tailscale/tailscale#13117).
        dev=$(${pkgs.iproute2}/bin/ip -o route show default | ${pkgs.gawk}/bin/awk '{print $5; exit}')
        if [ -z "$dev" ]; then
          # Fail rather than skip: a subnet router with no default route is
          # already broken (avoid a silent no-op).
          echo "no default route; cannot apply UDP GRO tuning" >&2
          exit 1
        fi
        ${pkgs.ethtool}/bin/ethtool -K "$dev" rx-udp-gro-forwarding on rx-gro-list off
      '';
    };
  };
}
