{
  config,
  lib,
  pkgs,
  ...
}:

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
      # Use this for torrent migrations and the like: https://github.com/jslay88/qbt_migrate
      profileDir = "/mnt/media/qbittorrent";
      serverConfig = {
        LegalNotice.Accepted = true;
        BitTorrent.Session = {
          QueueingSystemEnabled = false;

          # Headroom on a ~100 Mbit/s uplink to avoid saturating it and starving the ACKs of
          # every other device.
          GlobalUPSpeedLimit = 7000; # kB/s (56 Mbps)
          AlternativeGlobalDLSpeedLimit = 15000; # kB/s (120 Mbps)
          AlternativeGlobalUPSpeedLimit = 3750; # kB/s (30 Mbps)

          # Peer caps, mostly to limit the churn of short-lived flows through the
          # router's connection table rather than to limit throughput.
          MaxConnections = 300; # instead of 500 default
          MaxConnectionsPerTorrent = 50; # instead of 100 default
          MaxUploads = 8; # instead of 20 default
          MaxUploadsPerTorrent = 2; # instead of 4 default

          DefaultSavePath = "/mnt/bulk/to-stream";
        };
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
