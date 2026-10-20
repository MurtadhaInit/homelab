{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.homelab.caddy;

  services = [
    {
      name = "qbit";
      proxy = "localhost:${toString config.services.qbittorrent.webuiPort}";
    }
    {
      name = "jellyfin";
      proxy = "localhost:8096";
    }
    {
      name = "syncthing";
      proxy = "localhost:8384";
    }
    {
      name = "adguard";
      proxy = "localhost:${lib.last (lib.splitString ":" config.services.adguardhome.settings.http.address)}";
    }
    {
      name = "prowlarr";
      proxy = "localhost:${toString config.services.prowlarr.settings.server.port}";
    }
    {
      name = "sonarr";
      proxy = "localhost:${toString config.services.sonarr.settings.server.port}";
    }
    {
      name = "sabnzbd";
      proxy = "localhost:8080";
    }
    {
      name = "seerr";
      proxy = "localhost:${toString config.services.seerr.port}";
    }
    {
      name = "arcane";
      proxy = "10.20.30.41:3552";
    }
    {
      name = "dozzle";
      proxy = "10.20.30.41:8080";
    }
    {
      name = "homeassistant";
      proxy = "10.20.30.42:80";
    }
  ]
  ++ proxmoxServices;

  # Proxmox nodes are standalone (not clustered).
  # Keyed by node name so the subdomain matches the hostname.
  proxmoxServices = lib.mapAttrsToList (node: address: {
    name = node;
    proxy = "${address}:8006";
    upstreamHttps = true; # Proxmox only serves HTTPS (self-signed)
  }) cfg.proxmoxHosts;

  mkReverseProxy =
    svc:
    if (svc.upstreamHttps or false) then
      ''
        reverse_proxy https://${svc.proxy} {
          transport http {
            tls_insecure_skip_verify
          }
        }''
    else
      "reverse_proxy ${svc.proxy}";

  mkVHost =
    svc:
    lib.nameValuePair "${svc.name}.${cfg.domain}" {
      extraConfig = ''
        tls {
          dns cloudflare {env.CF_API_TOKEN}
        }
        ${mkReverseProxy svc}
      '';
    };
in
{
  options.homelab.caddy = {
    enable = lib.mkEnableOption "Enable Caddy reverse proxy with homelab defaults";
    domain = lib.mkOption {
      type = lib.types.str;
      example = "home.murtadha.dev";
      description = "Base domain for service subdomains (e.g. jellyfin.<domain>), served over HTTPS via Cloudflare DNS-01";
    };
    cloudflareTokenFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to file containing the Cloudflare API token";
    };
    proxmoxHosts = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        prox = "10.20.30.40";
      };
      description = ''
        Proxmox nodes to proxy, keyed by node name and mapped to the node's IP.
        Each entry gets a `<node>.<domain>` vhost pointing at its Web UI (8006).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.caddy = {
      enable = true;
      package = pkgs.caddy.withPlugins {
        plugins = [ "github.com/caddy-dns/cloudflare@v0.2.4" ];
        hash = "sha256-xRJ5evsAJ2akg47j3Bt6YDXJOgX88B/rKNP50KSVyNY=";
      };
      virtualHosts = lib.listToAttrs (map mkVHost services);
    };

    systemd.services.caddy.serviceConfig.EnvironmentFile = cfg.cloudflareTokenFile;

    # 80 only serves Caddy's automatic HTTP -> HTTPS redirects
    networking.firewall.allowedTCPPorts = [
      80
      443
    ];
    networking.firewall.allowedUDPPorts = [ 443 ]; # HTTP/3
  };
}
