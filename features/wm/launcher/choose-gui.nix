{ lib, mkFeature, ... }:

let
  mkChoose =
    config: pkgs:
    let
      choose = "${config.features.choose-gui.package}/bin/choose";
      font = config.features.font;
      mono = font.fonts.monospace;
      theme = config.features.theme;
    in
    pkgs.writeShellScript "choose" # bash
      ''
        /usr/bin/pkill -f '^${choose}'
        exec ${choose}${
          lib.optionalString font.enable " -f ${lib.escapeShellArg mono.name} -s ${toString (mono.size * 3 / 2)}"
          + lib.optionalString theme.enable " -c ${theme.colors.base0D} -b ${theme.colors.base02}"
        } "$@"
      '';
in
mkFeature {
  name = "choose-gui";

  doc = {
    summary = "choose, a fuzzy finder for macOS, as launcher, password menu and passphrase prompt";
    description = ''
      Installs and configures choose (choose-gui).

      If the `theme` and `font` features are enabled, choose's visuals will be adapted
      accordingly.

      - `enableLauncher`: Sets choose as the global app launcher and sets
        `globals.apps.launcher` to the choose bin path so other features can
        reference it
      - `enablePasswordManager`: Sets choose as the password manager. Requires the
        `password-store` feature to be enabled. Sets `globals.apps.passwordManager`
        to the bin path of choose so other features can reference it
      - `enablePinentry`: Sets choose as the pinentry application, asking for
        passphrases with its password mode (`-P`). Requires the `gnupg` feature to
        be enabled

      ```nix
      features = {
        choose-gui = {
          enable = true;
          enableLauncher = false;
        };
        password-store.enable = true;
      };
      ```
    '';
  };

  options =
    { config, pkgs, ... }:
    let
      inherit (lib) mkOption types;
      enabled = config.features.choose-gui.enable;
    in
    {
      package = mkOption {
        type = types.package;
        ## TODO: use nixpkgs version once updated (-P flag)
        default = pkgs.choose-gui.overrideAttrs {
          version = "1.5.0-unstable-2026-01-20";
          src = pkgs.fetchFromGitHub {
            owner = "chipsenkbeil";
            repo = "choose";
            rev = "8e83b711b1ad377ea58aa4ac8034e5c5e4310c33";
            hash = "sha256-OArdN7whm3vMr0Wiv5hiDReotBsA6KNbZDH7FTzyqgY=";
          };
        };
        defaultText = lib.literalMD "`pkgs.choose-gui` built from upstream master, for password mode (`-P`)";
        description = "The choose-gui package to use. `enablePinentry` needs one with password mode (`-P`)";
      };
      enableLauncher = mkOption {
        type = types.bool;
        defaultText = lib.literalExpression "config.features.choose-gui.enable";
        default = enabled;
        description = "Use this feature as the global launcher";
      };
      enablePinentry = mkOption {
        type = types.bool;
        defaultText = lib.literalExpression "config.features.choose-gui.enable";
        default = enabled;
        description = "Use this feature as the global pinentry";
      };
      enablePasswordManager = mkOption {
        type = types.bool;
        defaultText = lib.literalExpression "config.features.choose-gui.enable";
        default = enabled;
        description = "Use this feature as the global password manager";
      };
    };

  globals =
    { config, pkgs, ... }:
    let
      cfg = config.features.choose-gui;
      cmd = mkChoose config pkgs;

      launcher =
        pkgs.writeShellScript "choose-launcher" # bash
          ''
            dirs=(/Applications /System/Applications "$HOME/Applications" /System/Library/CoreServices/Finder.app)
            choice=$(
              /usr/bin/find "''${dirs[@]}" -maxdepth 2 -name '*.app' 2>/dev/null \
                | /usr/bin/sed 's|.*/||; s|\.app$||' \
                | /usr/bin/sort -u \
                | ${cmd}
            )
            [ -n "$choice" ] && /usr/bin/open -a "$choice"
          '';

      pass =
        pkgs.writeShellScriptBin "choose-pass" # bash
          ''
            ${lib.optionalString config.features.password-store.enable ''export PASSWORD_STORE_DIR="${config.features.password-store.storeDir}"''}
            ${lib.optionalString config.features.gnupg.enable ''export GNUPGHOME="${config.features.gnupg.storeDir}"''}
            export PATH="${lib.makeBinPath [ config.features.password-store.package ]}:$PATH"

            entry=$(
              /usr/bin/find "$PASSWORD_STORE_DIR" -type f -name '*.gpg' 2>/dev/null \
                | /usr/bin/sed -e "s|^$PASSWORD_STORE_DIR/||" -e 's/\.gpg$//' \
                | /usr/bin/sort \
                | ${cmd}
            )
            [ -z "$entry" ] && exit 0

            action=$(printf '%s\n' 'Copy password' 'Copy username' 'Copy URL' 'Copy OTP' \
              | ${cmd})

            copy () { printf '%s' "$1" | /usr/bin/pbcopy; }
            ## Pull a `key: value` line (case-insensitive) from the entry body.
            field () {
              pass show "$entry" \
                | /usr/bin/grep -iE "^($1):" \
                | /usr/bin/head -n1 \
                | /usr/bin/sed 's/^[^:]*:[[:space:]]*//'
            }

            case "$action" in
              'Copy password') copy "$(pass show "$entry" | /usr/bin/head -n1)" ;;
              'Copy username') copy "$(field 'username|user|login')" ;;
              'Copy URL')      copy "$(field 'url|website|site')" ;;
              'Copy OTP')      copy "$(pass otp "$entry")" ;;
            esac
          '';
    in
    {
      apps.launcher = lib.mkIf cfg.enableLauncher (lib.mkForce (toString launcher));

      apps.passwordManager = lib.mkIf (
        cfg.enablePasswordManager && config.features.password-store.enable
      ) (lib.mkForce "${pass}/bin/choose-pass");
    };

  home =
    { config, pkgs, ... }:
    let
      cfg = config.features.choose-gui;
      cmd = mkChoose config pkgs;

      pinentry =
        pkgs.writeShellScriptBin "pinentry-choose" # bash
          ''
            decode () { printf '%b' "''${1//%/\\x}"; }

            echo 'OK Pleased to meet you'
            while read -r command arg; do
              case "$command" in
                SETDESC)   desc=$(decode "$arg") ;;
                SETPROMPT) prompt=$(decode "$arg") ;;
                SETERROR)  error=$(decode "$arg") ;;
                GETINFO)   [ "$arg" = pid ] && echo "D $$" ;;
                GETPIN)
                  pin=$(${cmd} -P -p "''${error:-$prompt}" </dev/null) \
                    || { error=; echo 'ERR 83886179 Operation cancelled'; continue; }
                  error=
                  [ -n "$pin" ] && echo "D ''${pin//%/%25}"
                  ;;
                CONFIRM)
                  [ "$(printf 'Yes\nNo\n' | ${cmd} -p "''${desc%%$'\n'*}")" = Yes ] \
                    || { echo 'ERR 83886194 Not confirmed'; continue; }
                  ;;
                BYE) exit 0 ;;
              esac
              echo OK
            done
          '';
    in
    lib.mkMerge [
      { home.packages = [ cfg.package ]; }

      (lib.mkIf (cfg.enablePinentry && config.features.gnupg.enable) {
        services.gpg-agent.pinentry.package = lib.mkForce pinentry;
      })
    ];
}
