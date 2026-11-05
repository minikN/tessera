{ lib, inputs }:

let
  mkFeature = import ./mk-feature.nix { inherit lib; };
  mkHost = import ./mk-host.nix { inherit lib; };
  mkSchemeAttrs = import ./mk-scheme-attrs.nix { inherit lib; };
  mkElispConfig = import ./mk-elisp-config.nix { inherit lib; };
  discover = import ./discover.nix { inherit lib; };
  types = import ./types.nix { inherit lib; };
  setsOf = import ./sets.nix { inherit lib; };
  evalOptions = import ./eval-options.nix { inherit lib; };

  helpers = {
    inherit mkFeature mkElispConfig;
    tessera = { inherit types; };
  };
  features = discover.discoverFeatures ../features helpers;

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
in
{
  inherit
    mkFeature
    mkHost
    mkSchemeAttrs
    mkElispConfig
    mkFlake
    mkDocs
    types
    features
    ;
  inherit (discover) discoverFeatures discoverHosts;
}
