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

  outputs = inputs: {
    lib = import ./lib { lib = inputs.nixpkgs.lib; inherit inputs; };
    hardwareProfiles = builtins.attrNames inputs.nixos-hardware.nixosModules;
  };
}
