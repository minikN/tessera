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

  outputs =
    inputs:
    let
      lib = import ./lib {
        lib = inputs.nixpkgs.lib;
        inherit inputs;
      };
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems =
        f: inputs.nixpkgs.lib.genAttrs systems (system: f inputs.nixpkgs.legacyPackages.${system});
    in
    {
      inherit lib;

      overlays.default = lib.overlay;

      packages = forAllSystems (
        pkgs:
        {
          docs = lib.mkDocs {
            inherit pkgs;
            inherit (lib) features;
            sourceUrl = "https://github.com/minikN/tessera/blob/main";
          };
        }
        ## `pkgs.tessera.<category>.<name>` as `<category>-<name>`
        // inputs.nixpkgs.lib.concatMapAttrs (
          category:
          inputs.nixpkgs.lib.mapAttrs' (name: inputs.nixpkgs.lib.nameValuePair "${category}-${name}")
        ) (pkgs.extend lib.overlay).tessera
      );

      checks = forAllSystems (
        pkgs:
        {
          docs = lib.checkDocs {
            inherit pkgs;
            inherit (lib) features;
          };

          formatting =
            pkgs.runCommandLocal "formatting-check" { nativeBuildInputs = [ pkgs.nixfmt ]; } # bash
              ''
                cd ${./.}
                find . -name '*.nix' -exec nixfmt --check {} +
                touch $out
              '';
        }
        // import ./tests {
          inherit (inputs.nixpkgs) lib;
          inherit pkgs inputs;
          tessera = lib;
        }
      );

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);
    };
}
