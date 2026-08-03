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
      proxy = "localhost:${toString config.services.adguardhome.port}";
    }
    {
      name = "prowlarr";
      proxy = "localhost:9696";
    }
    {
      name = "sonarr";
      proxy = "localhost:8989";
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
      name = "portainer";
      proxy = "10.20.30.41:9443";
      upstreamHttps = true; # Portainer 2.18+ only serves on HTTPS (self-signed)
    }
    {
      name = "proxmox";
      proxy = "${cfg.proxmoxAddress}:8006";
      upstreamHttps = true;
    }
    {
      name = "qui";
      proxy = "localhost:7476";
    }
    {
      name = "stash";
      proxy = "localhost:${toString config.services.stash.settings.port}";
    }
  ];

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

  mkHttpBlock = svc: ''
    http://${svc.name}.${cfg.domain} {
    	${mkReverseProxy svc}
    }
  '';

  mkHttpsBlock = svc: ''
    ${svc.name}.${cfg.publicDomain} {
    	tls {
    		dns cloudflare {env.CF_API_TOKEN}
    	}
    	${mkReverseProxy svc}
    }
  '';

  # Build the Caddyfile directly and pass it via configFile to bypass the NixOS
  # module's Caddyfile-formatted derivation, which calls `cp --no-preserve=mode`.
  # That fails when building via Determinate Nix's native Linux builder on macOS
  # due to how Apple's Virtualization.framework / VirtioFS handles permission
  # semantics across the host/guest boundary. Tracked upstream at:
  # https://github.com/DeterminateSystems/nix-src/issues/421
  # Once fixed, switch to services.caddy.virtualHosts (cleaner, gets per-vhost
  # access logs, build-time validation).
  caddyfile = pkgs.writeText "Caddyfile" (
    lib.concatMapStrings mkHttpBlock services
    + lib.optionalString (cfg.publicDomain != null) (lib.concatMapStrings mkHttpsBlock services)
  );
in
{
  options.homelab.caddy = {
    enable = lib.mkEnableOption "Enable Caddy reverse proxy with homelab defaults";
    domain = lib.mkOption {
      type = lib.types.str;
      default = "home.lan";
      description = "Base domain for service subdomains (e.g. jellyfin.<domain>)";
    };
    publicDomain = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Public domain for HTTPS via Cloudflare DNS-01 (e.g. home.murtadha.dev)";
    };
    cloudflareTokenFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to file containing the Cloudflare API token";
    };
    proxmoxAddress = lib.mkOption {
      type = lib.types.str;
      description = "IP address of the Proxmox host";
    };
  };

  config = lib.mkIf cfg.enable {
    services.caddy = {
      enable = true;
      package = pkgs.caddy.withPlugins {
        plugins = [ "github.com/caddy-dns/cloudflare@v0.2.4" ];
        hash = "sha256-8yZDrejNKsaUnUaTUFYbarWNmxafqp2z2rWo+XRsxV8=";
      };
      configFile = caddyfile;
    };

    systemd.services.caddy.serviceConfig.EnvironmentFile = cfg.cloudflareTokenFile;

    networking.firewall.allowedTCPPorts = [ 80 ] ++ lib.optional (cfg.publicDomain != null) 443;
  };
}
