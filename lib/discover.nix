{ lib }:

rec {
  nixFilesIn = dir:
    builtins.filter
      (f: lib.hasSuffix ".nix" (toString f))
      (lib.filesystem.listFilesRecursive dir);

  readsOf = import ./reads.nix { inherit lib; };

  discoverFeatures = featuresDir: helpers:
    map
      (f:
        let feature = (import f) ({ inherit lib; } // helpers); in
        feature // {
          file = f;
          doc = if feature.doc == null then null
            else feature.doc // { reads = readsOf f feature.name; };
        })
      (nixFilesIn featuresDir);

  discoverHosts = hostsDir:
    map
      (f: {
        name = lib.removeSuffix ".nix" (baseNameOf (toString f));
        file = f;
      })
      (nixFilesIn hostsDir);
}
