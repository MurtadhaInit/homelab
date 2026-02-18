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
      webuiPort = 9090;
      # torrentingPort =
      # profileDir =  # the config/state location
      serverConfig = {
        Preferences = {
          WebUI = {
            Username = "murtadha";
            # Generate a password: nix run git+https://codeberg.org/feathecutie/qbittorrent_password:main -- -p <password>
            Password_PBKDF2 = "@ByteArray(RnWLrLhy2VE0cc1a9eoOIQ==:65Rrbv6+y2MCujH2bJdr/5lccDZXyHmYzv3M/yGAr72uwnmdBCeQh6axlkczaT9JnQ+1MHWzEr3QnfSTgdNfjQ==)"; # TODO: for testing. replace later with proper secrets
          };
        };
      };
    };
  };
}
