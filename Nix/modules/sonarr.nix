{
  config,
  lib,
  ...
}:

let
  cfg = config.homelab.sonarr;
in
{
  options.homelab.sonarr = {
    enable = lib.mkEnableOption "Enable Sonarr with homelab defaults";
    apiKeyFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Path to a file containing the Sonarr API key as a systemd EnvironmentFile.
        Must contain: SONARR__AUTH__APIKEY=<32-char hex string>
      '';
    };
  };

  # Auth credentials (username/password) are stored in Sonarr's database,
  # not config.xml, so they cannot be set declaratively.
  # Complete the one-time setup wizard on first visit to configure auth.
  config = lib.mkIf cfg.enable {
    services.sonarr = {
      enable = true;
      user = "murtadha";
      group = "murtadha";
      dataDir = "/mnt/media/sonarr";
      openFirewall = true; # default port is 8989
      settings = {
        auth = {
          authenticationMethod = "Forms";
          authenticationRequired = "Enabled";
        };
        server = {
          bindaddress = "localhost";
        };
      };
      environmentFiles = [ cfg.apiKeyFile ];
    };
  };
}
