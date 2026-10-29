{ lib, mkFeature, ... }:

mkFeature {
  name = "choose-gui";

  doc = {
    summary = "choose, a fuzzy finder for macOS, as launcher and password menu.";
    description = ''
      Uses choose (choose-gui), styled with the shared colours (and the
      monospace font when the font feature is enabled), for two global apps:

      - **Launcher** (`globals.apps.launcher`): lists the installed `.app`
        bundles and opens the one you pick. Disable with `enableLauncher = false`.
      - **Password manager** (`globals.apps.passwordManager`): pick a pass
        entry, then copy its password, username, URL or one-time code. It uses
        the password-store and gnupg features' settings. Disable with
        `enablePasswordManager = false`.
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

      ## Themed choose invocation: monospace font + base16 colours. choose wants
      ## bare hex (no leading #), so use the plain scheme, not withHashtag.
      chooseCmd =
        let
          font = config.features.font;
          mono = font.fonts.monospace;
          scheme = config.features.theme.scheme;
        in
        "${cfg.package}/bin/choose"
        + lib.optionalString font.enable " -f ${lib.escapeShellArg mono.name} -s ${toString (mono.size * 3 / 2)}"
        + " -c ${scheme.base0D}"
        + " -b ${scheme.base02}";

      ## macOS drun-equivalent: list installed .app bundles, fuzzy-pick one with
      ## choose-gui, then open it. (choose-gui's binary is `choose`.)
      launcher = pkgs.writeShellScript "choose-launcher" ''
        dirs=(/Applications /System/Applications "$HOME/Applications")
        choice=$(
          /usr/bin/find "''${dirs[@]}" -maxdepth 2 -name '*.app' 2>/dev/null \
            | /usr/bin/sed 's|.*/||; s|\.app$||' \
            | /usr/bin/sort -u \
            | ${chooseCmd}
        )
        [ -n "$choice" ] && /usr/bin/open -a "$choice"
      '';

      ## pass front-end: pick an entry with choose-gui, then a second prompt for
      ## what to copy (password / username / URL / OTP) onto the clipboard.
      passExec = pkgs.writeShellScriptBin "choose-pass" ''
        export PASSWORD_STORE_DIR="${config.features.password-store.storeDir}"
        export GNUPGHOME="${config.features.gnupg.storeDir}"
        export PATH="${lib.makeBinPath [ config.features.password-store.package ]}:$PATH"

        entry=$(
          /usr/bin/find "$PASSWORD_STORE_DIR" -type f -name '*.gpg' 2>/dev/null \
            | /usr/bin/sed -e "s|^$PASSWORD_STORE_DIR/||" -e 's/\.gpg$//' \
            | /usr/bin/sort \
            | ${chooseCmd}
        )
        [ -z "$entry" ] && exit 0

        action=$(printf '%s\n' 'Copy password' 'Copy username' 'Copy URL' 'Copy OTP' \
          | ${chooseCmd})

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

      apps.passwordManager = lib.mkIf cfg.enablePasswordManager (
        lib.mkForce "${passExec}/bin/choose-pass"
      );
    };

  home =
    { config, ... }:
    {
      home.packages = [ config.features.choose-gui.package ];
    };
}
