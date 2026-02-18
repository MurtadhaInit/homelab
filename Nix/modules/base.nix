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

  time.timeZone = "Asia/Amman";

  environment.systemPackages = with pkgs; [
    neovim
    htop
    curl
    git
  ];

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };
}
