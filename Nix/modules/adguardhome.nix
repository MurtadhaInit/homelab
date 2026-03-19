{
  config,
  lib,
  ...
}:

let
  cfg = config.homelab.adguardhome;
in
{
  options.homelab.adguardhome = {
    enable = lib.mkEnableOption "Enable AdGuard Home with homelab defaults";
    domain = lib.mkOption {
      type = lib.types.str;
      default = "home.lan";
      description = "Local domain to resolve via DNS rewrites";
    };
    lanAddress = lib.mkOption {
      type = lib.types.str;
      default = "10.20.30.50";
      description = "LAN IP that all subdomains of the local domain should resolve to";
    };
  };

  config = lib.mkIf cfg.enable {
    services.adguardhome = {
      enable = true;
      openFirewall = true; # only for the Web UI port
      port = 3080; # Web UI port - the default of 3000 conflicts with the Grafana module
      mutableSettings = true;
      settings = {
        # NOTE: The schema version matches the package version
        # Available options: https://github.com/AdguardTeam/AdGuardHome/wiki/Configuration#configuration-file
        users = [
          {
            name = "murtadha";
            # Generate with: htpasswd -B -n -b murtadha YOUR_PASSWORD
            password = "$2y$05$AxQ/AIqdVsHBBHIEoqPrAerYfZ.Oo9T8oXaoJXVSTiSYW3mtm2HlK";
          }
        ];
        statistics = {
          interval = "720h"; # 30 days
        };
        querylog = {
          interval = "720h"; # 30 days
        };

        dns = {
          upstream_dns = [
            # "https://dns11.quad9.net/dns-query" # quad9 - ECS, Malware blocking, DNSSEC Validation
            # "tls://dns11.quad9.net" # quad9 - ECS, Malware blocking, DNSSEC Validation
            "https://dns.quad9.net/dns-query" # quad9 - Malware Blocking, DNSSEC Validation
            "tls://dns.quad9.net" # quad9 - Malware Blocking, DNSSEC Validation
          ];
          upstream_mode = "parallel";
          fallback_dns = [
            "https://security.cloudflare-dns.com/dns-query"
            # "https://cloudflare-dns.com/dns-query"
            "9.9.9.11"
            "149.112.112.11"
            "2620:fe::11"
            "2620:fe::fe:11"
            "1.1.1.2"
            "1.0.0.2"
            "2606:4700:4700::1112"
            "2606:4700:4700::1002"
          ];
          # Bootstrap DNS must be plain IPs — used to resolve the DoH hostnames above
          bootstrap_dns = [
            "1.1.1.1"
            "1.0.0.1"
            "8.8.8.8"
          ];
          enable_dnssec = true;

          # rDNS: resolve PTR queries for private IPs via the router, which knows
          # device hostnames from DHCP leases.
          # NOTE: add the gateway address for each network using Adguard Home
          # as its DNS server in Unifi
          use_private_ptr_resolvers = true;
          local_ptr_upstreams = [ "10.20.30.1" ];

          # Safe to disable on a LAN-only server (not exposed to the internet)
          ratelimit = 0;
          refuse_any = false;
        };

        filtering = {
          protection_enabled = true;
          filtering_enabled = true;
          # Wildcard rewrite: any subdomain of the local domain
          # resolves to the IP where a reverse-proxy handles routing.
          rewrites = [
            {
              domain = "*.${cfg.domain}";
              answer = cfg.lanAddress;
              enabled = true;
            }
          ];
        };

        filters = [
          {
            enabled = true;
            url = "https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt";
            name = "AdGuard DNS filter";
            id = 1;
          }
          {
            enabled = true;
            url = "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts";
            name = "Steven Black's unified hosts";
            id = 2;
          }
          # {
          #   enabled = true;
          #   url = "https://big.oisd.nl";
          #   name = "OISD Big";
          #   id = 3;
          # }
          # {
          #   enabled = true;
          #   url = "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/pro.txt";
          #   name = "HaGeZi Pro";
          #   id = 4;
          # }
        ];
      };
    };

    # AdGuard Home replaces systemd-resolved (which binds to port 53) as the DNS resolver.
    services.resolved.enable = false;

    # DNS port (53) is not opened by the module's openFirewall (only the web UI)
    networking.firewall = {
      allowedTCPPorts = [ 53 ];
      allowedUDPPorts = [ 53 ];
    };
  };
}
