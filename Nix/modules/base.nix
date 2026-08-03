# Shared base configuration for all NixOS hosts.
# Import this in every host to get a consistent baseline.
{ pkgs, ... }:

{
  nixpkgs.config.allowUnfree = true;

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };

  time.timeZone = "Asia/Amman";

  environment.systemPackages = with pkgs; [
    neovim
    wget
    htop
    curl
    git
  ];

  # Install the terminfo outputs of the terminals we might SSH in from (ghostty,
  # kitty, wezterm, ...) so TERM resolves for every user and every SSH client,
  # rather than depending on the client shipping its own terminfo on connect.
  environment.enableAllTerminfo = true;

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };
}
