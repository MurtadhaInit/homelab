{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.homelab.jellyfin;
in
{
  options.homelab.jellyfin = {
    enable = lib.mkEnableOption "Enable Jellyfin server with homelab defaults";
  };

  config = lib.mkIf cfg.enable {
    services.jellyfin = {
      enable = true;
      openFirewall = true; # won't sync with port changes made in the GUI afterwards
      # The default Web UI port is 8096
      configDir = "/mnt/media/jellyfin/config";
      dataDir = "/mnt/media/jellyfin/data";
      cacheDir = "/mnt/media/jellyfin/cache";
    };

    environment.systemPackages = [
      pkgs.jellyfin-ffmpeg # for Intro Skipper: https://github.com/intro-skipper/intro-skipper
    ];
  };
}
