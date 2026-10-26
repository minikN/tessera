{ lib, inputs }:

let
  mkFeature = import ./mk-feature.nix { inherit lib; };
  mkHost = import ./mk-host.nix { inherit lib; };
  mkSchemeAttrs = import ./mk-scheme-attrs.nix { inherit lib; };
  mkElispConfig = import ./mk-elisp-config.nix { inherit lib; };
  discover = import ./discover.nix { inherit lib; };
  types = import ./types.nix { inherit lib; };
  setsOf = import ./sets.nix { inherit lib; };
  evalDocs = import ./eval-docs.nix { inherit lib; };
  mkFlake = import ./mk-flake.nix {
    inherit lib types mkFeature mkHost mkElispConfig;
    tesseraInputs = inputs;
    inherit (discover) discoverFeatures discoverHosts;
  };
in
{
  inherit mkFeature mkHost mkSchemeAttrs mkElispConfig mkFlake types setsOf evalDocs;
  inherit (discover) discoverFeatures discoverHosts;
}
