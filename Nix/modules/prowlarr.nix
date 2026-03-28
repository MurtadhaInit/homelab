{
  config,
  lib,
  ...
}:

let
  cfg = config.homelab.prowlarr;
in
{
  options.homelab.prowlarr = {
    enable = lib.mkEnableOption "Enable Prowlarr indexer manager with homelab defaults";
    apiKeyFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Path to a file containing the Prowlarr API key as a systemd EnvironmentFile.
        Must contain: PROWLARR__AUTH__APIKEY=<32-char hex string>
        This overrides the API key at runtime for stable inter-*arr communication.
      '';
    };
  };

  # Auth credentials (username/password) are stored in Prowlarr's database,
  # not config.xml, so they cannot be set declaratively.
  # Complete the one-time setup wizard on first visit to configure auth.
  config = lib.mkIf cfg.enable {
    services.prowlarr = {
      enable = true;
      openFirewall = true; # Default port is 9696
      dataDir = "/mnt/media/prowlarr";
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
