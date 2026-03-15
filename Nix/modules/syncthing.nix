{
  config,
  lib,
  ...
}:

let
  cfg = config.homelab.syncthing;
in
{
  options.homelab.syncthing = {
    enable = lib.mkEnableOption "Enable Syncthing with homelab defaults";
    guiPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Path to a file containing the plaintext password for the Web GUI";
    };
    keyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Path to the Syncthing private key (key.pem)";
    };
    certFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Path to the Syncthing certificate (cert.pem)";
    };
  };

  config = lib.mkIf cfg.enable {
    services.syncthing = {
      enable = true;
      user = "murtadha";
      group = "murtadha";
      key = cfg.keyFile;
      cert = cfg.certFile;
      dataDir = "/mnt/media/syncthing";
      # NOTE: this won't open the GUI port
      openDefaultPorts = true; # TCP/UDP 22000 for transfers and UDP 21027 for discovery
      guiPasswordFile = cfg.guiPasswordFile;
      guiAddress = "0.0.0.0:8384";
      settings = {
        gui = {
          user = "murtadha";
        };
        devices = {
          MBP = {
            id = "CYLNY5H-GWUW324-OXEJJTA-E4RGJC4-W5X6HGP-J5DZE6F-E54XXBL-WYQ2MQK";
          };
        };
        folders = {
          documents = {
            id = "documents";
            path = "/mnt/media/documents";
            label = "Documents";
            ignorePerms = true;
            versioning = {
              type = "staggered";
              params = {
                maxAge = "31536000"; # keep versions up to 1 year
              };
            };
            devices = [ "MBP" ];
          };
        };
      };
    };

    # 8384 is the default GUI port to allow access from the network
    networking.firewall.allowedTCPPorts = [ 8384 ];
  };
}
