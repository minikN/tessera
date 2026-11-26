{
  lib,
  pkgs,
  tessera,
  inputs,
}:

## Tessera's tests, as `checks.<system>.*`
let
  pkgs' = pkgs.extend tessera.overlay;
  platform = if pkgs.stdenv.hostPlatform.isDarwin then "darwin" else "nixos";
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
  inherit lib platform;
  inherit (hosts) expect check emacsCheck;
}
// lib.mapAttrs' (name: lib.nameValuePair "ert-${name}") (
  import ./packages/emacs {
    inherit lib;
    pkgs = pkgs';
  }
)
