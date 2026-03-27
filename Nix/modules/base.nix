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
    htop
    curl
    git
  ];

  # buildEnv doesn't link ghostty.terminfo into the system-path despite it
  # being in systemPackages (multi-output package limitation). TERMINFO is
  # checked first in the terminfo lookup chain, so pointing it directly at
  # the store path bypasses the system-path entirely (for other terminal
  # types the lookup falls through to $TERMINFO_DIRS).
  environment.sessionVariables.TERMINFO = "${pkgs.ghostty.terminfo}/share/terminfo";

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };
}
