{ lib, mkFeature, ... }:

mkFeature {
  name = "choose-gui";

  doc = {
    summary = "choose, a fuzzy finder for macOS, as launcher and password menu.";
    description = ''
      Installs and configures choose (choose-gui).

      If the `theme` and `font` features are enabled, choose's visuals will be adapted
      accordingly.

      - `enableLauncher`: Sets choose as the global app launcher and sets
        `globals.apps.launcher` to the choose bin path so other features can
        reference it
      - `enablePasswordManager`: Sets choose as the password manager. Requires the
        `password-store` feature to be enabled. Sets `globals.apps.passwordManager`
        to the bin path of choose so other features can reference it.

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
      inherit (lib) mkOption mkPackageOption types;
      enabled = config.features.choose-gui.enable;
    in
    {
      package = mkPackageOption pkgs "choose-gui" { };
      enableLauncher = mkOption {
        type = types.bool;
        defaultText = lib.literalExpression "config.features.choose-gui.enable";
        default = enabled;
        description = "Use this feature as the global launcher.";
      };
      enablePasswordManager = mkOption {
        type = types.bool;
        defaultText = lib.literalExpression "config.features.choose-gui.enable";
        default = enabled;
        description = "Use this feature as the global password manager.";
      };
    };

  globals =
    { config, pkgs, ... }:
    let
      cfg = config.features.choose-gui;

      cmd =
        let
          font = config.features.font;
          mono = font.fonts.monospace;
          theme = config.features.theme;
          scheme = theme.scheme;
        in
        "${cfg.package}/bin/choose"
        + lib.optionalString font.enable " -f ${lib.escapeShellArg mono.name} -s ${toString (mono.size * 3 / 2)}"
        + lib.optionalString theme.enable " -c ${scheme.base0D} -b ${scheme.base02}";

      launcher = pkgs.writeShellScript "choose-launcher" ''
        dirs=(/Applications /System/Applications "$HOME/Applications" /System/Library/CoreServices/Finder.app)
        choice=$(
          /usr/bin/find "''${dirs[@]}" -maxdepth 2 -name '*.app' 2>/dev/null \
            | /usr/bin/sed 's|.*/||; s|\.app$||' \
            | /usr/bin/sort -u \
            | ${cmd}
        )
        [ -n "$choice" ] && /usr/bin/open -a "$choice"
      '';

      pass = pkgs.writeShellScriptBin "choose-pass" ''
        export PASSWORD_STORE_DIR="${config.features.password-store.storeDir}"
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
    { config, ... }:
    {
      home.packages = [ config.features.choose-gui.package ];
    };
}
