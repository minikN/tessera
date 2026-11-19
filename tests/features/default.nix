{ lib, expect }:

## Feature-specific checks. Each `<category>/<feature>.nix` here, mirroring
## `features/`, is a function of `lib` and `expect` (see `../hosts.nix`) that
## returns checks made with `expect`, named `<feature>-<name>`.
let
  files = builtins.filter (f: lib.hasSuffix ".nix" (toString f) && f != ./default.nix) (
    lib.filesystem.listFilesRecursive ./.
  );
in
lib.mergeAttrsList (
  map (
    file:
    let
      feature = lib.removeSuffix ".nix" (baseNameOf file);
    in
    lib.mapAttrs' (name: check: lib.nameValuePair "${feature}-${name}" (check "${feature}-${name}")) (
      import file { inherit lib expect; }
    )
  ) files
)
