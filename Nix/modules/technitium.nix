{
  config,
  lib,
  ...
}:

let
  cfg = config.homelab.technitium;
in
{
  options.homelab.technitium = {
    enable = lib.mkEnableOption "Enable Technitium DNS Server with homelab defaults";
  };

  config = lib.mkIf cfg.enable {
    services.technitium-dns-server = {
      enable = true;
      openFirewall = true;
      # Default ports:
      # UDP 53        — DNS
      # TCP 53        — DNS
      # TCP 5380      — Web UI (HTTP)
      # TCP 53443     — Web UI (HTTPS)
    };
  };
}
