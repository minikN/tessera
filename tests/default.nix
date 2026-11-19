{
  lib,
  pkgs,
  tessera,
  inputs,
}:

## Tessera's tests, as `checks.<system>.*`
let
  pkgs' = pkgs.extend tessera.overlay;
  hosts = import ./hosts.nix {
    inherit
      lib
      pkgs
      tessera
      inputs
      ;
  };
in
hosts.checks
// import ./features {
  inherit lib;
  inherit (hosts) expect;
}
// lib.mapAttrs' (name: lib.nameValuePair "ert-${name}") (
  import ./packages/emacs {
    inherit lib;
    pkgs = pkgs';
  }
)
