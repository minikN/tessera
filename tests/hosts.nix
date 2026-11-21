{
  lib,
  pkgs,
  tessera,
  inputs,
}:

## Evaluates hosts built from tessera's features alone, without building them:
## a bare host, one per feature with only that feature (and its parent)
## enabled, and one with all of them and all their boolean options that are
## off by default turned on, each on NixOS and macOS. The bare and
## all hosts are evaluated as standalone home-manager configurations too.
## Failed assertions and warnings fail the check. `frameworkChecks` check the
## assertions `mkFeature` gives every feature. `features/` has the
## feature-specific checks, made with `expect` and `check`.
let
  globals = {
    user = "user";
    fullName = "User";
    email = "user@example.com";
    stateVersion = lib.trivial.release;
  };

  platforms = {
    nixos = {
      name = "NixOS";
      host = {
        system = "x86_64-linux";
        nixos.fileSystems."/" = {
          device = "/dev/sda1";
          fsType = "ext4";
        };
      };
    };
    darwin = {
      name = "macOS";
      host.system = "aarch64-darwin";
    };
  };

  ## Features left out of the host with all features, as they conflict with
  ## one that stays
  conflicting = [ "bash" ];

  nameOf = f: lib.concatStringsSep "." (lib.toList f.name);

  ## `features` setting of a host that enables `f` and its parent
  enableFeature =
    f:
    lib.foldl' lib.recursiveUpdate { } (
      map (path: lib.setAttrByPath (path ++ [ "enable" ]) true) (
        f.requiredNames ++ [ (lib.toList f.name) ]
      )
    );

  mkHost =
    platform: host:
    tessera.mkHost {
      inherit inputs globals;
      inherit (tessera) features;
      name = "test";
      host = lib.recursiveUpdate platforms.${platform}.host host;
    };

  ## Messages of the failed assertions and the warnings of `config`
  problemsOf =
    config: map (a: a.message) (builtins.filter (a: !a.assertion) config.assertions) ++ config.warnings;

  ## What to evaluate of `host`: its system and, with `home`, its standalone
  ## home-manager configuration
  partsOf =
    host: home:
    {
      system = {
        inherit (host.systemConfig) config;
        drv = host.systemConfig.config.system.build.toplevel;
      };
    }
    // lib.optionalAttrs home {
      home = {
        inherit (host.homeConfig) config;
        drv = host.homeConfig.activationPackage;
      };
    };

  bare = lib.mapAttrs (platform: _: mkHost platform { }) platforms;

  ## Whether `f` can be enabled on `platform`
  supports =
    platform: f:
    f.supports platform {
      inherit (bare.${platform}.systemConfig) config options pkgs;
    };

  ## A check evaluating `parts` of a host
  evalCheck =
    name: parts:
    let
      problems = lib.concatLists (
        lib.mapAttrsToList (part: p: map (m: "${part}: ${m}") (problemsOf p.config)) parts
      );
      drvPaths = lib.mapAttrsToList (_: p: builtins.unsafeDiscardStringContext p.drv.drvPath) parts;
    in
    if problems == [ ] then
      pkgs.runCommandLocal "test-${name}" { } ''
        printf '%s\n' ${lib.escapeShellArgs drvPaths} > $out
      ''
    else
      throw ''
        test host ${name}:
        ${lib.concatMapStrings (p: "  - ${p}\n") problems}'';

  ## A check named `name` that the host with `features` on `platform` fails
  ## each assertion and gives each warning in `messages`. Assertions and
  ## warnings that fail to evaluate on a bad host are skipped; messages are
  ## only read from failed assertions.
  expect =
    {
      platform,
      features,
      messages,
    }:
    name:
    let
      inherit ((mkHost platform { inherit features; }).systemConfig.config) assertions warnings;
      failed =
        a:
        builtins.tryEval a.assertion == {
          success = true;
          value = false;
        };
      ## Warnings too may fail to evaluate on a bad host
      warnings' = builtins.tryEval (builtins.deepSeq warnings warnings);
      given =
        m:
        builtins.any (a: failed a && lib.hasInfix m a.message) assertions
        || warnings'.success && builtins.any (lib.hasInfix m) warnings'.value;
      missing = builtins.filter (m: !given m) messages;
    in
    if missing == [ ] then
      pkgs.runCommandLocal "test-${name}" { } "touch $out"
    else
      throw ''
        test host ${name}: expected
        ${lib.concatMapStrings (m: "  - ${m}\n") missing}'';

  ## A check named `name` that the host made of the other attributes (`features`
  ## and `home`, `nixos` or `darwin` modules) on `platform` evaluates cleanly
  ## and passes `assertions`: NixOS-style assertions about its system `config`
  ## and the user's home-manager config `home`
  check =
    {
      platform,
      assertions,
      ...
    }@spec:
    name:
    let
      host = removeAttrs spec [
        "platform"
        "assertions"
      ];
      inherit ((mkHost platform host).systemConfig) config;
      failed = builtins.filter (a: !a.assertion) (assertions {
        inherit config;
        home = config.home-manager.users.${globals.user};
      });
      problems = problemsOf config ++ map (a: a.message) failed;
    in
    if problems == [ ] then
      pkgs.runCommandLocal "test-${name}" { } "touch $out"
    else
      throw ''
        test host ${name}:
        ${lib.concatMapStrings (p: "  - ${p}\n") problems}'';

  ## Assertions of every feature, with sway and aerospace as examples
  frameworkChecks = {
    parent-disabled = expect {
      platform = "darwin";
      features.emacs.eglot.enable = true;
      messages = [ "features.emacs.eglot requires features.emacs to be enabled." ];
    };
    nixos-feature-on-darwin = expect {
      platform = "darwin";
      features.sway.enable = true;
      messages = [ "features.sway is not available on macOS." ];
    };
    darwin-feature-on-nixos = expect {
      platform = "nixos";
      features.aerospace.enable = true;
      messages = [ "features.aerospace is not available on NixOS." ];
    };
    server-without-home-manager =
      name:
      let
        host = tessera.mkHost {
          inherit inputs;
          inherit (tessera) features;
          name = "test";
          host = lib.recursiveUpdate platforms.nixos.host {
            homeManager = false;
            features = {
              home.enable = false;
              user.enable = false;
            };
            nixos.system.stateVersion = "26.05";
          };
        };
      in
      assert host.homeConfig == null;
      assert !(host.systemConfig.config ? home-manager);
      evalCheck name (partsOf host false);
  };

  perPlatform =
    platform:
    let
      supported = builtins.filter (supports platform) tessera.features;
      enabled = lib.foldl' lib.recursiveUpdate { } (
        map enableFeature (builtins.filter (f: !builtins.elem (nameOf f) conflicting) supported)
      );
      ## Whether the feature at `path` or one above it is in `enabled`
      isEnabled =
        path:
        path != [ ] && (lib.attrByPath (path ++ [ "enable" ]) false enabled || isEnabled (lib.init path));
      ## Boolean options of the enabled features that are off by default,
      ## other than the features' own `enable`
      optIns = builtins.filter (
        o:
        o.type.name == "bool"
        && o.default or null == false
        && !builtins.elem o.loc (
          map (f: [ "features" ] ++ lib.toList f.name ++ [ "enable" ]) tessera.features
        )
        && isEnabled (lib.init (lib.tail o.loc))
      ) (lib.collect lib.isOption bare.${platform}.systemConfig.options.features);
      all = lib.foldl' lib.recursiveUpdate enabled (
        map (o: lib.setAttrByPath (lib.tail o.loc) true) optIns
      );
    in
    {
      "host-${platform}-bare" = evalCheck "${platform}-bare" (partsOf bare.${platform} true);
      "host-${platform}-all" = evalCheck "${platform}-all" (
        partsOf (mkHost platform {
          features = all;
          ## A stand-in for `sway.useGlobalBar`, as tessera has no bar feature
          home.globals.apps.bar = "bar";
        }) true
      );
    }
    // lib.listToAttrs (
      map (
        f:
        let
          name = "${platform}-${lib.replaceStrings [ "." ] [ "-" ] (nameOf f)}";
        in
        lib.nameValuePair "host-${name}" (
          evalCheck name (partsOf (mkHost platform { features = enableFeature f; }) false)
        )
      ) supported
    );
in
{
  inherit expect check;
  checks =
    perPlatform "nixos"
    // perPlatform "darwin"
    // lib.mapAttrs' (
      name: check: lib.nameValuePair "expect-${name}" (check "expect-${name}")
    ) frameworkChecks;
}
