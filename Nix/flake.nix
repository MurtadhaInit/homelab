{
  description = "NixOS infrastructure deployed with deploy-rs";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.darwin.follows = ""; # save some space by not downloading darwin deps
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      deploy-rs,
      agenix,
      ...
    }@inputs:
    let
      system = "x86_64-linux";

      # deploy-rs's Rust package isn't in any cache once its nixpkgs follows ours, so the
      # activation wrapper rebuilt it on every deploy. nixpkgs' own deploy-rs is cached, so
      # take the binary from there and only the activation lib from the flake input.
      deployPkgs = nixpkgs.legacyPackages.${system}.appendOverlays [
        deploy-rs.overlays.default
        (final: prev: {
          deploy-rs = {
            inherit (nixpkgs.legacyPackages.${system}) deploy-rs;
            inherit (prev.deploy-rs) lib;
          };
        })
      ];
    in
    {
      nixosConfigurations = {
        nixos-ct = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = [
            ./hosts/nixos-ct
            agenix.nixosModules.default
          ];
        };
      };

      deploy.nodes = {
        nixos-ct = {
          hostname = "nixos-ct";
          sshUser = "root";
          profiles.system = {
            user = "root";
            path = deployPkgs.deploy-rs.lib.activate.nixos self.nixosConfigurations.nixos-ct;
          };
        };
      };

      # `nix run .#deploy-rs` drives deploys with the same cached CLI the activation
      # wrapper embeds; deploy-rs.lib is keyed by the systems deploy-rs supports.
      packages = nixpkgs.lib.genAttrs (builtins.attrNames deploy-rs.lib) (s: {
        deploy-rs = nixpkgs.legacyPackages.${s}.deploy-rs;
      });

      # To prevent many possible mistakes
      checks = builtins.mapAttrs (_: deployLib: deployLib.deployChecks self.deploy) deploy-rs.lib;
    };
}
