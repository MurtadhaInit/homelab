{
  config,
  lib,
  ...
}:

let
  cfg = config.homelab.sabnzbd;
in
{
  options.homelab.sabnzbd = {
    enable = lib.mkEnableOption "Enable SABnzbd usenet download client with homelab defaults";
    secretsFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Path to an INI file containing SABnzbd login and API secrets.
        Must contain:
          [misc]
          api_key = <32-char hex>
          nzb_key = <32-char hex>
          username = <login username>
          password = <login password>
      '';
    };
    serverSecretsFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Path to an INI file containing Usenet server(s) configuration and credentials.
        Must contain:
          [servers]
          [[<server-name>]]
          host = <server hostname>
          port = <port>
          ssl = <1 for true, 0 for false>
          ssl_verify = <3 for strict, 2 for allow injection, 0 for none>
          username = <usenet username>
          password = <usenet password>
          connections = <number of connections>
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # config_merge.py crashes if sabnzbd.ini is in the merge list but missing.
    # With allowConfigWrite = true the existing config is included in the merge,
    # so pre-create an empty file to survive the first deploy.
    systemd.tmpfiles.rules = [
      "f /var/lib/sabnzbd/sabnzbd.ini 0600 murtadha murtadha -"
    ];

    services.sabnzbd = {
      enable = true;
      user = "murtadha";
      group = "murtadha";
      openFirewall = true; # default port is 8080
      # Required: stateVersion < 26.05 defaults configFile to the INI path,
      # which makes the module ignore settings and secretFiles entirely.
      configFile = null;
      allowConfigWrite = true;
      secretFiles = [
        cfg.secretsFile
        cfg.serverSecretsFile
      ];
      settings.misc = {
        download_dir = "/mnt/media/downloads/incomplete";
        complete_dir = "/mnt/media/downloads/complete";
        par2_multicore = 1;
        fail_hopeless_jobs = 1;
        host_whitelist = builtins.concatStringsSep ", " [
          "sabnzbd.${config.homelab.caddy.domain}"
          "sabnzbd.${config.homelab.caddy.publicDomain}"
        ];
      };
    };
  };
}
