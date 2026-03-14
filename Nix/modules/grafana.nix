{
  config,
  lib,
  ...
}:

let
  cfg = config.homelab.grafana;
in
{
  options.homelab.grafana = {
    enable = lib.mkEnableOption "Enable Grafana with homelab defaults";
    secretKeyFile = lib.mkOption {
      type = lib.types.str;
      description = "Path to a file containing Grafana's secret_key, used to encrypt secrets in the DB (API keys, datasource credentials, etc.)";
    };
    adminPasswordFile = lib.mkOption {
      type = lib.types.str;
      description = "Path to a file containing the Grafana admin password";
    };
  };

  config = lib.mkIf cfg.enable {
    services.grafana = {
      enable = true;
      settings = {
        security = {
          secret_key = "$__file{${cfg.secretKeyFile}}";
          admin_user = "murtadha";
          admin_password = "$__file{${cfg.adminPasswordFile}}";
        };
        server = {
          # Bind to all interfaces so it's reachable from the LAN.
          # Corresponds to: [server].http_addr in grafana.ini
          http_addr = "0.0.0.0";
          # Corresponds to: [server].http_port in grafana.ini
          http_port = 3000;
        };
      };

      # Provisioning lets you declare datasources and dashboards as code
      # instead of configuring them manually through the Grafana UI.
      # These map directly to Grafana's provisioning YAML files:
      # https://grafana.com/docs/grafana/latest/administration/provisioning/
      provision = {
        enable = true;
        datasources.settings.datasources = [
          {
            # Registers the local Prometheus instance as a datasource.
            # Corresponds to: datasources[].type + url in provisioning YAML.
            name = "Prometheus";
            type = "prometheus";
            url = "http://127.0.0.1:${toString config.services.prometheus.port}";
            isDefault = true;
            # Allow editing queries in the UI (for learning/exploration).
            editable = true;
          }
        ];
      };
    };

    networking.firewall.allowedTCPPorts = [ 3000 ];
  };
}
