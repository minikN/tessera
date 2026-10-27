{
  description = "Composable features for NixOS, nix-darwin and home-manager.";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
  };

  outputs = inputs:
    let
      lib = import ./lib { lib = inputs.nixpkgs.lib; inherit inputs; };
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
    in
    {
      inherit lib;
      hardwareProfiles = builtins.attrNames inputs.nixos-hardware.nixosModules;

      packages = inputs.nixpkgs.lib.genAttrs systems (system: {
        docs = lib.mkDocs {
          pkgs = inputs.nixpkgs.legacyPackages.${system};
          inherit (lib) features;
        };
      });
    };
}
