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
  };

  config = lib.mkIf cfg.enable {
    services.syncthing = {
      enable = true;
      user = "murtadha";
      group = "murtadha";
      dataDir = "/mnt/media/syncthing";
      # NOTE: this won't open the GUI port
      openDefaultPorts = true; # TCP/UDP 22000 for transfers and UDP 21027 for discovery
      guiPasswordFile = cfg.guiPasswordFile;
      # Don't clobber devices/folders (or devices for folders) added through the GUI
      overrideDevices = false;
      overrideFolders = false;
      guiAddress = "0.0.0.0:8384";
      settings = {
        gui = {
          user = "murtadha";
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
          };
        };
      };
    };

    # 8384 is the default GUI port to allow access from the network
    networking.firewall.allowedTCPPorts = [ 8384 ];
  };
}
