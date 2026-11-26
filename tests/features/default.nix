{
  lib,
  platform,
  expect,
  check,
  emacsCheck,
}:

## Feature-specific checks. Each `<category>/<feature>.nix` here, mirroring
## `features/`, is a function of `lib`, `platform`, `expect`, `check` and
## `emacsCheck` (see `../hosts.nix`) that returns checks made with them, named
## `<feature>-<name>`. Checks are included only when their `platform` matches
## the current flake system.
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
      checks = import file {
        inherit lib platform;
        check = spec: if spec.platform == platform then check spec else null;
        expect = spec: if spec.platform == platform then expect spec else null;
        emacsCheck = spec: if spec.platform == platform then emacsCheck spec else null;
      };
    in
    lib.mapAttrs' (name: check: lib.nameValuePair "${feature}-${name}" (check "${feature}-${name}")) (
      lib.filterAttrs (_: check: check != null) checks
    )
  ) files
)
