{ lib }:

{
  name,
  options ? { },
  home ? null,
  nixos ? null,
  darwin ? null,
  globals ? null,
  enableByDefault ? false,
  ## [ "home" "nixos" "darwin" ] - optional. Only set where it can't be derived automatically
  platforms ? null,
  ## { summary; description; nixos; darwin; }
  doc ? null,
  ...
}:

let
  inherit (lib)
    mkIf
    mkOption
    setAttrByPath
    getAttrFromPath
    concatStringsSep
    types
    ;

  fname = if builtins.isList name then name else [ name ];
  optionPath = [ "features" ] ++ fname;
  enablePath = optionPath ++ [ "enable" ];
  niceName = concatStringsSep "." fname;

  requiredNames = lib.optional (builtins.length fname > 1) (lib.init fname);

  ## Whether the feature works on `platform`
  supports =
    platform:
    {
      config,
      options,
      pkgs,
      ...
    }:
    let
      opts = getAttrFromPath optionPath options;
      hasBlock =
        {
          home = home != null;
          nixos = nixos != null || home != null;
          darwin = darwin != null || home != null;
        }
        .${platform};
      packageAvailable =
        !(opts ? package)
        || lib.meta.availableOn pkgs.stdenv.hostPlatform (
          getAttrFromPath (optionPath ++ [ "package" ]) config
        );
    in
    hasBlock && packageAvailable && (platforms == null || builtins.elem platform platforms);

  ## Adds `platform` and `requires` assertions for a feature
  checks =
    platform:
    args@{ config, options, ... }:
    let
      enabled = getAttrFromPath enablePath config;
      explicit = (getAttrFromPath enablePath options).highestPrio < 1500; # set, not just the default
      platformName =
        {
          nixos = "NixOS";
          darwin = "macOS";
        }
        .${platform};
    in
    [
      {
        assertion = !(enabled && explicit) || supports platform args;
        message = "features.${niceName} is not available on ${platformName}.";
      }
    ]
    ++ map (required: {
      assertion = !enabled || getAttrFromPath ([ "features" ] ++ required ++ [ "enable" ]) config;
      message = "features.${niceName} requires features.${concatStringsSep "." required} to be enabled.";
    }) requiredNames;

  callBlock = block: args: if builtins.isFunction block then block args else block;

  mkBody =
    block:
    args@{
      config,
      pkgs,
      lib,
      ...
    }:
    let
      mod = callBlock block args;
      rest = builtins.removeAttrs mod [
        "imports"
        "options"
      ];
    in
    {
      imports = mod.imports or [ ];
      config = mkIf (getAttrFromPath enablePath config) rest;
    };

  commonModule =
    args@{
      config,
      pkgs,
      lib,
      ...
    }:
    let
      userOptions = callBlock options args;
      userGlobals = if globals == null then { } else callBlock globals args;
    in
    {
      options = setAttrByPath optionPath (
        {
          enable = mkOption {
            type = types.bool;
            default = enableByDefault;
            example = !enableByDefault;
            description = "Whether to enable the ${niceName} feature.";
          };
        }
        // userOptions
      );
      config.globals = userGlobals;
    };
in
{
  inherit
    name
    doc
    globals
    platforms
    requiredNames
    supports
    checks
    commonModule
    ;
  nixosModule = if nixos == null then null else mkBody nixos;
  darwinModule = if darwin == null then null else mkBody darwin;
  homeModule = if home == null then null else mkBody home;
}
