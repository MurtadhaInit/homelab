{
  config,
  lib,
  ...
}:

let
  cfg = config.homelab.stash;
in
{
  options.homelab.stash = {
    enable = lib.mkEnableOption "Enable Stash media organizer with homelab defaults";

    libraryPath = lib.mkOption {
      type = lib.types.str;
      description = ''
        Directory that Stash scans for media.

        Must not contain whitespace: the upstream module passes every library path
        to systemd's `BindReadOnlyPaths=`, which takes a whitespace-separated list,
        and NixOS renders list entries unquoted. A path with a space is therefore
        read as several non-existent paths and the unit fails to start.
      '';
    };

    excludeImages = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Skip still images while scanning, keeping the library scenes-only.
        Set to false to also import image sets as galleries.
      '';
    };

    username = lib.mkOption {
      type = lib.types.str;
      default = "murtadha";
      description = "Username for the Stash web UI login.";
    };

    passwordFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Path to a file containing the *bcrypt hash* of the web UI password — not the
        password itself. Stash checks a login with `bcrypt.CompareHashAndPassword`
        against the raw `password` value in config.yml, so a plaintext password here
        locks you out instead of failing loudly.
      '';
    };

    jwtSecretKeyFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to a file containing the secret used to sign JWTs.";
    };

    sessionStoreKeyFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to a file containing the session store secret.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = builtins.match "[^[:space:]]+" cfg.libraryPath != null;
        message = ''
          homelab.stash.libraryPath ("${cfg.libraryPath}") contains whitespace, which
          systemd's BindReadOnlyPaths= would split into several bogus paths.
          Use a whitespace-free directory.
        '';
      }
    ];

    services.stash = {
      enable = true;

      # A dedicated user rather than the shared `murtadha` one: the upstream module
      # pins `users.users.<user>.home` to dataDir, which would move HOME out from
      # under every other service running as `murtadha`. Stash only needs to read
      # the library, so group membership is enough.
      user = "stash"; # the default
      group = "stash"; # the default

      dataDir = "/mnt/media/stash"; # e.g. generated previews/sprites

      openFirewall = false; # reached through the reverse proxy only

      inherit (cfg)
        username
        passwordFile
        jwtSecretKeyFile
        sessionStoreKeyFile
        ;

      # config.yml is regenerated from `settings` on every start (Settings-page UI
      # tweaks are transient and git stays the source of truth).
      # Scenes, performers and tags live in the SQLite database.
      mutableSettings = false;

      # Scrapers and plugins are still installed from the UI's built-in community
      # source. Pinning them in Nix is impractical here: the module derives one
      # manifest per directory, and CommunityScrapers mixes `scrapers/<Name>/<Name>.yml`
      # with flat `scrapers/<Name>.yml`, so the flat ones would all collide.
      mutablePlugins = true;
      mutableScrapers = true;

      settings = {
        host = "localhost"; # the default
        port = 9999; # the default
        stash = [
          {
            path = cfg.libraryPath;
            excludeimage = cfg.excludeImages;
          }
        ];
      };
    };

    # Traverse and read the bind-mounted media, which is owned by murtadha:murtadha.
    users.users.stash.extraGroups = [ "murtadha" ];

    # BindReadOnlyPaths= fails the unit when its source is missing, so the library
    # directory has to exist.
    systemd.tmpfiles.rules = [
      "d ${dirOf cfg.libraryPath} 0750 murtadha murtadha -"
      "d ${cfg.libraryPath} 0750 murtadha murtadha -"
    ];
  };
}
