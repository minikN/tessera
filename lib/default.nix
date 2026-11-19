{ lib, inputs }:

let
  mkFeature = import ./mk-feature.nix { inherit lib; };
  mkHost = import ./mk-host.nix { inherit lib overlay; };
  mkSchemeAttrs = import ./mk-scheme-attrs.nix { inherit lib; };
  mkElispPackage = import ./mk-elisp-package.nix { inherit lib; };
  mkElispConfig = import ./mk-elisp-config.nix { inherit lib mkElispPackage; };
  discover = import ./discover.nix { inherit lib; };
  types = import ./types.nix { inherit lib; };
  setsOf = import ./sets.nix { inherit lib; };
  evalOptions = import ./eval-options.nix { inherit lib; };

  helpers = {
    inherit mkFeature mkElispConfig;
    tessera = { inherit types mkDocs features; };
  };
  features = discover.discoverFeatures ../features helpers;

  ## Tessera's own packages, from `packages/<category>/<name>.nix`, as
  ## `pkgs.tessera.<category>.<name>`
  overlay = final: _prev: {
    tessera = lib.packagesFromDirectoryRecursive {
      callPackage = lib.callPackageWith (final // { inherit mkElispPackage; });
      directory = ../packages;
    };
  };

  mkFlake = import ./mk-flake.nix {
    inherit
      lib
      helpers
      features
      mkHost
      ;
    tesseraInputs = inputs;
    inherit (discover) discoverFeatures discoverHosts;
  };
  mkDocs = import ./mk-docs.nix {
    inherit
      lib
      inputs
      evalOptions
      setsOf
      ;
  };
  checkDocs = import ./check-docs.nix { inherit lib evalOptions; };
in
{
  inherit
    mkFeature
    mkHost
    mkSchemeAttrs
    mkElispPackage
    mkElispConfig
    mkFlake
    mkDocs
    checkDocs
    types
    features
    overlay
    ;
  inherit (discover) discoverFeatures discoverHosts;
  hardwareProfiles = builtins.attrNames inputs.nixos-hardware.nixosModules;
}
