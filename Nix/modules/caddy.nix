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
      name = "prometheus";
      proxy = "localhost:${toString config.services.prometheus.port}";
    }
    {
      name = "grafana";
      proxy = "localhost:${toString config.services.grafana.settings.server.http_port}";
    }
    {
      name = "adguard";
      proxy = "localhost:${toString config.services.adguardhome.port}";
    }
  ];

  mkHttpBlock = svc: ''
    http://${svc.name}.${cfg.domain} {
    	reverse_proxy ${svc.proxy}
    }
  '';

  mkHttpsBlock = svc: ''
    ${svc.name}.${cfg.publicDomain} {
    	tls {
    		dns cloudflare {env.CF_API_TOKEN}
    	}
    	reverse_proxy ${svc.proxy}
    }
  '';

  # Build the Caddyfile directly to bypass the NixOS module's `caddy fmt`
  # formatting check, which fails with Caddy 2.11+ (exit code 1 when
  # the input needed reformatting).
  caddyfile = pkgs.writeText "Caddyfile" (
    ''
      {
      	metrics {
      		per_host
      	}
      }
    ''
    + lib.concatMapStrings mkHttpBlock services
    + ''

      http://proxmox.${cfg.domain} {
      	reverse_proxy https://${cfg.proxmoxAddress}:8006 {
      		transport http {
      			tls_insecure_skip_verify
      		}
      	}
      }
    ''
    + lib.optionalString (cfg.publicDomain != null) (
      lib.concatMapStrings mkHttpsBlock services
      + ''

        proxmox.${cfg.publicDomain} {
        	tls {
        		dns cloudflare {env.CF_API_TOKEN}
        	}
        	reverse_proxy https://${cfg.proxmoxAddress}:8006 {
        		transport http {
        			tls_insecure_skip_verify
        		}
        	}
        }
      ''
    )
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
        hash = "sha256-8HpPZ/VoiV/k0ZYcnXHmkwuEYKNpURKTN19aYZRLPoM=";
      };
      configFile = caddyfile;
    };

    systemd.services.caddy.serviceConfig.EnvironmentFile = cfg.cloudflareTokenFile;

    networking.firewall.allowedTCPPorts = [ 80 ] ++ lib.optional (cfg.publicDomain != null) 443;
  };
}
