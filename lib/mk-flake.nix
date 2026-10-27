{ lib, helpers, tesseraInputs, mkHost, discoverFeatures, discoverHosts, ... }@tessera:

## Build every host in `hosts` from tessera's features plus the user's own.
{ inputs ? { }
, globals
, hosts
, features ? null
}:

let
  allInputs = tesseraInputs // inputs;

  allFeatures = tessera.features
    ++ lib.optionals (features != null) (discoverFeatures features helpers);

  builtHosts = builtins.listToAttrs (map
    (h: {
      inherit (h) name;
      value = mkHost {
        inputs = allInputs;
        features = allFeatures;
        inherit globals;
        inherit (h) name file;
      };
    })
    (discoverHosts hosts));

  onPlatform = platform:
    lib.mapAttrs (_: v: v.systemConfig)
      (lib.filterAttrs (_: v: v.platform == platform) builtHosts);
in
{
  nixosConfigurations = onPlatform "nixos";
  darwinConfigurations = onPlatform "darwin";
  homeConfigurations = lib.mapAttrs (_: v: v.homeConfig) builtHosts;
}
