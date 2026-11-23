{ lib, mkFeature, ... }:

let
  mkSchemeAttrs = import ../../lib/mk-scheme-attrs.nix { inherit lib; };
  rawSchemes = import ../../schemes;
  baseNames = map (i: "base0${lib.toHexString i}") (lib.range 0 15);

  ## default syntax roles
  syntaxDefaults = {
    comment = "base03";
    docstring = "base03";
    variable = "base08";
    constant = "base09";
    number = "base09";
    type = "base0A";
    string = "base0B";
    builtin = "base0C";
    regexp = "base0C";
    function = "base0D";
    keyword = "base0E";
    operator = "base05";
    preprocessor = "base0F";
  };

  other = polarity: if polarity == "dark" then "light" else "dark";
in
mkFeature {
  name = "theme";

  doc = {
    summary = "A colour scheme with a light and a dark variant, used by features";
    description = ''
      Holds the base16 colour scheme that other features take their colours from.
      `scheme` comes in a light and a dark variant, `polarity` picks one of them,
      and `wallpaper` sets a background for window managers that show one.

      **Built-in schemes:**
      - `default` (modus themes based)
      - `monokai-pro`

      **Custom theme:**
      Set `scheme` to the scheme itself instead of a name: an attrset with a `light`
      and a `dark` variant, each holding all 16 base16 colours (`base00` to `base0F`)
      in plain hex, without `#`.

      `polarity` and `enableToggle` pick between the variants. If the theme only has
      one variant, set `polarity` to it and disable `enableToggle`.

      **Syntax roles**
      - editors colour strings, keywords, functions and so on after the base16 styling
      guide, e.g. strings in `base0B`. A scheme that pairs them with other colours lists
      those roles in `syntax`, each naming the base16 colour to use.

      ```nix
      features.theme = {
        enable = true;
        scheme = "monokai-pro";
        polarity = "dark";
      };
      ```

      Custom inline theme:

      ```nix
      features.theme.scheme = {
        light = {
          base00 = "fafafa"; base01 = "eeeeee"; base02 = "dddddd"; base03 = "999999";
          base04 = "777777"; base05 = "222222"; base06 = "444444"; base07 = "111111";
          base08 = "c82829"; base09 = "f5871f"; base0A = "eab700"; base0B = "718c00";
          base0C = "3e999f"; base0D = "4271ae"; base0E = "8959a8"; base0F = "a3685a";
        };
        dark = {
          base00 = "1d1f21"; base01 = "282a2e"; base02 = "373b41"; base03 = "969896";
          base04 = "b4b7b4"; base05 = "c5c8c6"; base06 = "e0e0e0"; base07 = "ffffff";
          base08 = "cc6666"; base09 = "de935f"; base0A = "f0c674"; base0B = "b5bd68";
          base0C = "8abeb7"; base0D = "81a2be"; base0E = "b294bb"; base0F = "a3685a";
        };
        syntax = { string = "base0A"; keyword = "base08"; }; # optnal
      }
      ```

      Custom theme file:

      ```nix
      features.theme.scheme = import ./my-scheme.nix;
      ```
    '';
    nixos = ''
      - `enableToggle`: builds the other polarity as a NixOS specialisation and
        installs `toggle-theme` (also as a desktop entry), which switches
        between light and dark at runtime without asking for a password
    '';
  };

  options =
    { config, ... }:
    let
      inherit (lib) mkEnableOption mkOption types;
    in
    {
      polarity = mkOption {
        type = types.enum [
          "light"
          "dark"
        ];
        default = "light";
        description = "Which variant of `scheme` to use";
      };

      scheme = mkOption {
        type = types.coercedTo (types.enum (lib.attrNames rawSchemes)) (name: rawSchemes.${name}) (
          types.submodule {
            options = {
              light = mkOption {
                type = types.nullOr (types.attrsOf types.str);
                default = null;
                description = "`base00` to `base0F` in plain hex";
              };
              dark = mkOption {
                type = types.nullOr (types.attrsOf types.str);
                default = null;
                description = "`base00` to `base0F` in plain hex";
              };
              syntax = mkOption {
                type = types.submodule {
                  options = lib.mapAttrs (
                    role: slot:
                    mkOption {
                      type = types.enum baseNames;
                      default = slot;
                      description = "Base16 colour of the `${role}` syntax role";
                    }
                  ) syntaxDefaults;
                };
                default = { };
                description = "Which base16 colour each syntax role takes";
              };
            };
          }
        );
        default = "default";
        description = "Base16 scheme: the name of a built-in one, or the scheme itself (`light`, `dark` and optionally `syntax`)";
      };

      colors = mkOption {
        type = types.attrs;
        readOnly = true;
        default =
          let
            inherit (config.features.theme) scheme polarity;
          in
          ## The default scheme stands in for a missing variant, which the
          ## feature's assertions report
          mkSchemeAttrs (
            if scheme.${polarity} != null then scheme.${polarity} else rawSchemes.default.${polarity}
          );
        defaultText = lib.literalExpression "config.features.theme.scheme.\${config.features.theme.polarity}";
        description = ''
          The colours in use. The `polarity` variant of `scheme` in plain hex.
          `colors.withHashtag.*` exposes the `#`-prefixed form
        '';
      };

      wallpaper = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Wallpaper path. `null` falls back to a solid colour from `colors`";
      };

      enableToggle = mkEnableOption "runtime light/dark switch (NixOS only)";
    };

  nixos =
    { config, ... }:
    let
      cfg = config.features.theme;
      otherPolarity = other cfg.polarity;
    in
    lib.mkIf cfg.enableToggle {
      assertions = [
        {
          assertion = cfg.scheme.${otherPolarity} != null;
          message = ''features.theme.scheme has no "${otherPolarity}" variant, which enableToggle needs.'';
        }
      ];

      security.sudo.extraRules = [
        {
          runAs = "root";
          groups = [ "wheel" ];
          commands = [
            {
              command = "/nix/var/nix/profiles/system/specialisation/${otherPolarity}/bin/switch-to-configuration switch";
              options = [ "NOPASSWD" ];
            }
            {
              command = "/nix/var/nix/profiles/system/bin/switch-to-configuration switch";
              options = [ "NOPASSWD" ];
            }
          ];
        }
      ];

      ## Sibling config with polarity flipped. Activated by toggle-theme.
      specialisation.${otherPolarity}.configuration = {
        features.theme.polarity = lib.mkForce otherPolarity;
        home-manager.sharedModules = [ { features.theme.polarity = lib.mkForce otherPolarity; } ];
      };
    };

  home =
    { config, pkgs, ... }:
    let
      cfg = config.features.theme;
      otherPolarity = other cfg.polarity;
      toggler =
        pkgs.writeShellScriptBin "toggle-theme" # bash
          ''
            current=$(readlink /run/current-system)
            specialisation=$(readlink /nix/var/nix/profiles/system/specialisation/${otherPolarity})
            if [ "$current" = "$specialisation" ] || [ -z "$specialisation" ]; then
              sudo /nix/var/nix/profiles/system/bin/switch-to-configuration switch
            else
              sudo /nix/var/nix/profiles/system/specialisation/${otherPolarity}/bin/switch-to-configuration switch
            fi
          '';
    in
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = cfg.scheme.${cfg.polarity} != null;
            message = ''features.theme.scheme has no "${cfg.polarity}" variant, which polarity = "${cfg.polarity}" needs.'';
          }
        ];
      }

      ## The toggle switches NixOS specialisations
      (lib.mkIf (cfg.enableToggle && config.globals.platform == "nixos") {
        home.packages = [ toggler ];
        xdg.desktopEntries.toggle-theme = {
          name = "Toggle Theme";
          exec = "${toggler}/bin/toggle-theme";
        };
      })
    ];
}
