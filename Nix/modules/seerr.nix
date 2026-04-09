{
  config,
  lib,
  ...
}:

let
  cfg = config.homelab.seerr;
in
{
  options.homelab.seerr = {
    enable = lib.mkEnableOption "Enable Seerr with homelab defaults";
  };

  config = lib.mkIf cfg.enable {
    services.seerr = {
      enable = true;
      openFirewall = true; # Default port is 5055
    };
  };
}
