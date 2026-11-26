{ lib, overlay }:

{
  inputs,
  globals ? { },
  features,
  name,
  ## The host file, or its contents as `host`
  file ? null,
  host ? import file,
}:

let
  inherit (lib) mkDefault;

  system = host.system;
  platform = if lib.strings.hasInfix "darwin" system then "darwin" else "nixos";

  hostFeatures = host.features or { };
  hostNixos = host.nixos or { };
  hostDarwin = host.darwin or { };
  hostHome = host.home or { };
  homeManager = host.homeManager or true;

  hardwareModule = {
    imports = map (
      profile:
      inputs.nixos-hardware.nixosModules.${profile}
        or (throw "host ${name}: unknown hardware profile '${profile}'; see `tessera.lib.hardwareProfiles`")
    ) (host.hardware or [ ]);
  };

  ## Only used with Home Manager
  user =
    globals.user
      or (throw "host ${name}: globals.user is required when Home Manager is enabled; set globals.user or homeManager = false.");

  globalsOptionsModule = import ./globals-options.nix;

  staticGlobalsModule = { ... }: {
    config.globals.user = globals;
    config.globals.platform = platform;
  };

  ## A function gets the module arguments it asks for, like `pkgs`
  hostFeaturesModule =
    if builtins.isFunction hostFeatures then
      lib.setFunctionArgs (args: { config.features = hostFeatures args; }) (
        builtins.functionArgs hostFeatures
      )
    else
      { config.features = hostFeatures; };

  featureChecks =
    {
      config,
      options,
      pkgs,
      ...
    }:
    {
      assertions =
        builtins.concatMap (f: f.checks platform { inherit config options pkgs; }) features
        ++ lib.concatMap (
          f:
          let
            path = [ "features" ] ++ lib.toList f.name;
            enablePath = path ++ [ "enable" ];
            enabled = lib.getAttrFromPath enablePath config;
            explicit = (lib.getAttrFromPath enablePath options).highestPrio < 1500;
          in
          lib.optional (f.homeOnly) {
            assertion = homeManager || !(enabled && explicit);
            message = "features.${lib.concatStringsSep "." (lib.toList f.name)} requires Home Manager; set homeManager = true or disable the feature.";
          }
        ) features;
    };

  defaultUserModule = {
    config.features.user.enable = mkDefault (globals ? user);
  };

  filterNonNull = builtins.filter (m: m != null);

  commonFeatureModules = map (f: f.commonModule) features;
  homeFeatureModules = filterNonNull (map (f: f.homeModule) features);
  nixosFeatureModules = filterNonNull (map (f: f.nixosModule) features);
  darwinFeatureModules = filterNonNull (map (f: f.darwinModule) features);

  homeModules = [
    globalsOptionsModule
    staticGlobalsModule
    hostFeaturesModule
  ]
  ++ lib.optional (globals ? stateVersion) { home.stateVersion = mkDefault globals.stateVersion; }
  ++ commonFeatureModules
  ++ homeFeatureModules
  ++ [ hostHome ];

  systemHomeManagerModule = {
    home-manager.useGlobalPkgs = true;
    home-manager.useUserPackages = true;
    home-manager.backupFileExtension = "backup";
    home-manager.users.${user}.imports = homeModules;
  };

  systemModules = [
    globalsOptionsModule
    staticGlobalsModule
    hostFeaturesModule
    defaultUserModule
    {
      nixpkgs.config.allowUnfree = true;
      nixpkgs.overlays = [ overlay ];
    }
    featureChecks
  ]
  ++ lib.optional homeManager systemHomeManagerModule
  ++ commonFeatureModules
  ++ (if platform == "nixos" then nixosFeatureModules else darwinFeatureModules)
  ++ (
    if platform == "nixos" then
      [
        hostNixos
        hardwareModule
      ]
    else
      [ hostDarwin ]
  );

  systemConfig =
    if platform == "nixos" then
      inputs.nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs globals; };
        modules =
          lib.optional homeManager inputs.home-manager.nixosModules.home-manager
          ++ lib.optional (globals ? stateVersion) { system.stateVersion = mkDefault globals.stateVersion; }
          ++ systemModules;
      }
    else
      inputs.darwin.lib.darwinSystem {
        inherit system;
        specialArgs = { inherit inputs globals; };
        modules =
          lib.optional homeManager inputs.home-manager.darwinModules.home-manager
          ++ [ { system.stateVersion = mkDefault 6; } ]
          ++ systemModules;
      };

  homeConfig =
    if homeManager then
      builtins.seq user (
        inputs.home-manager.lib.homeManagerConfiguration {
          pkgs = import inputs.nixpkgs {
            inherit system;
            config.allowUnfree = true;
            overlays = [ overlay ];
          };
          extraSpecialArgs = { inherit inputs globals; };
          modules = homeModules;
        }
      )
    else
      null;
in
{
  inherit
    name
    platform
    system
    homeManager
    systemConfig
    homeConfig
    ;
}
