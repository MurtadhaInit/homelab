{ config, lib, ... }:

let
  cfg = config.homelab.qbittorrent;
in
{
  options.homelab.qbittorrent = {
    enable = lib.mkEnableOption "Enable qBittorrent-nox with homelab defaults";
  };

  config = lib.mkIf cfg.enable {
    services.qbittorrent = {
      enable = true;
      openFirewall = true;
      user = "murtadha";
      group = "murtadha";
      webuiPort = 9080;
      # torrentingPort =
      profileDir = "/mnt/media/qbittorrent";
      serverConfig = {
        LegalNotice.Accepted = true;
        BitTorrent.Session.QueueingSystemEnabled = false;
        Preferences = {
          WebUI = {
            # AlternativeUIEnabled = true;
            # RootFolder = "${pkgs.vuetorrent}/share/vuetorrent";
            Username = "murtadha";
            # Generate a password: nix run git+https://codeberg.org/feathecutie/qbittorrent_password:main -- -p <password>
            # TODO: for testing. replace later with proper secrets
            Password_PBKDF2 = "@ByteArray(FS2FD/7c7tMa1L+lG+7vng==:Cdl48KcH17YqJudyzVNC8KAG4q4kf78JLMfvtItTngcg4nBueXikO8kUf3Sg0R26Ltul/+tkKW7RkhYcCnwmsw==)";
          };
          General.Locale = "en";
        };
      };
    };
  };
}
