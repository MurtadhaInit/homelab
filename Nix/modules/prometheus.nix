{
  config,
  lib,
  ...
}:

let
  cfg = config.homelab.prometheus;
in
{
  options.homelab.prometheus = {
    enable = lib.mkEnableOption "Enable Prometheus with homelab defaults";
    proxmoxHostAddress = lib.mkOption {
      type = lib.types.str;
      description = "IP or hostname of the Proxmox host running node_exporter";
    };
  };

  config = lib.mkIf cfg.enable {
    services.prometheus = {
      enable = true;
      globalConfig.scrape_interval = "15s";
      scrapeConfigs = [
        {
          job_name = "proxmox-node";
          static_configs = [
            { targets = [ "${cfg.proxmoxHostAddress}:9100" ]; }
          ];
        }
        {
          job_name = "caddy";
          static_configs = [
            { targets = [ "localhost:2019" ]; }
          ];
        }
      ];
    };

    # Prometheus listens on port 9090 by default.
    networking.firewall.allowedTCPPorts = [ 9090 ];
  };
}
