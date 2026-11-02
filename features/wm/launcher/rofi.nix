{ lib, mkFeature, ... }:

let
  ## rasi theme. mkLiteral comes from home-manager (config.lib.formats.rasi).
  mkTheme =
    config:
    let
      mkLiteral = config.lib.formats.rasi.mkLiteral;
    in
    {
      "*" = with config.features.theme.colors.withHashtag; {
        border = 0;
        margin = 0;
        padding = 0;
        spacing = 0;

        bg0 = mkLiteral base01;
        bg1 = mkLiteral base02;

        fg0 = mkLiteral base05;
        fg1 = mkLiteral base06;

        urgent-color = mkLiteral base08;

        background-color = mkLiteral "transparent";
        text-color = mkLiteral "@fg0";
      };
      window = {
        location = mkLiteral "center";
        width = 768;
        height = 432;
        background-color = mkLiteral "@bg0";
        border = mkLiteral "2px";
        border-color = mkLiteral "@bg1";
        padding = mkLiteral "4px";
      };
      inputbar = {
        spacing = mkLiteral "8px";
        padding = mkLiteral "8px";
        background-color = mkLiteral "@bg1";
      };
      "prompt, entry, element-icon, element-text" = {
        vertical-align = mkLiteral "0.5";
      };
      prompt = {
        text-color = mkLiteral "@text-color";
      };
      textbox = {
        padding = mkLiteral "8px";
        background-color = mkLiteral "@bg1";
      };
      listview = {
        padding = mkLiteral "4px 0";
        lines = 8;
        columns = 1;
        fixed-height = true;
      };
      element = {
        padding = mkLiteral "8px";
        spacing = mkLiteral "8px";
      };
      "element normal normal" = {
        text-color = mkLiteral "@fg0";
      };
      "element normal urgent" = {
        text-color = mkLiteral "@urgent-color";
      };
      "element normal active" = {
        text-color = mkLiteral "@fg0";
      };
      "element alternate active" = {
        text-color = mkLiteral "@fg0";
      };
      "element selected" = {
        text-color = mkLiteral "@fg0";
      };
      "element selected normal, element selected active" = {
        background-color = mkLiteral "@bg1";
      };
      "element selected urgent" = {
        background-color = mkLiteral "@urgent-color";
      };
      "element-icon" = {
        size = mkLiteral "0.8em";
      };
      "element-text" = {
        text-color = mkLiteral "inherit";
      };
    };

  mkSettings =
    config:
    with config.features.rofi;
    {
      modi = "run,ssh,drun";
      drun-show-actions = showActions;
      show-icons = showIcons;

      kb-element-next = "Alt+n";
      kb-element-prev = "Alt+p";

      kb-page-next = "Super+n";
      kb-page-prev = "Super+p";

      kb-row-select = "Tab,Control+i";
      kb-secondary-paste = "Control+y";
      kb-remove-word-forward = "Alt+d";
      kb-remove-word-back = "Control+w,Control+BackSpace";
      kb-clear-line = "Control+slash";
    }
    // lib.optionalAttrs config.features.font.enable {
      font = with config.features.font.fonts.monospace; "${name} ${toString size}";
    };
in
mkFeature {
  name = "rofi";

  doc = {
    summary = "rofi as application launcher, password menu and passphrase prompt";
    description = ''
      Installs and configures rofi.

      If the `theme` and `font` features are enabled, rofi's visuals will be adapted
      accordingly.

      - `enableLauncher`: Sets rofi as the global app launcher and sets
        `globals.apps.launcher` to the rofi bin path so other features can
        reference it
      - `enablePasswordManager`: Sets rofi as the password manager. Requires the
        `password-store` feature to be enabled. It will install either `tessen`
        on wayland or a small shell script on X11 to interact with the password store.
        Sets `globals.apps.passwordManager` to the bin path of the script
      - `enablePinentry`: Sets rofi as the pinentry application. Requires the `gnupg`
        feature to be enabled

      ```nix
      features = {
        rofi = {
          enable = true;
          enablePinentry = false;
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
      enabled = config.features.rofi.enable;
    in
    {
      package = mkPackageOption pkgs "rofi" { };
      showActions = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to show drun actions";
      };
      showIcons = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to show icons";
      };
      enableLauncher = mkOption {
        type = types.bool;
        defaultText = lib.literalExpression "config.features.rofi.enable";
        default = enabled;
        description = "Use this feature as the global launcher";
      };
      enablePinentry = mkOption {
        type = types.bool;
        defaultText = lib.literalExpression "config.features.rofi.enable";
        default = enabled;
        description = "Use this feature as the global pinentry";
      };
      enablePasswordManager = mkOption {
        type = types.bool;
        defaultText = lib.literalExpression "config.features.rofi.enable";
        default = enabled;
        description = "Use this feature as the global password manager";
      };
      keybindings = mkOption {
        type = types.attrsOf types.str;
        default = { };
        example = {
          kb-row-select = "Tab";
        };
        description = "Keybindings (rofi's `kb-*` settings) merged over the defaults";
      };
    };

  globals =
    { config, pkgs, ... }:
    let
      cfg = config.features.rofi;
      pass = config.features.password-store.package;
      env = ''
        ${lib.optionalString config.features.password-store.enable ''export PASSWORD_STORE_DIR="${config.features.password-store.storeDir}"''}
        ${lib.optionalString config.features.gnupg.enable ''export GNUPGHOME="${config.features.gnupg.storeDir}"''}
      '';

      waylandPass = pkgs.writeShellScriptBin "tessen" ''
        ${env}
        export PATH="${lib.makeBinPath [ cfg.package ]}:$PATH"
        exec ${pkgs.tessen.override { inherit pass; }}/bin/tessen --pass pass --dmenu rofi "$@"
      '';

      x11Pass = pkgs.writeShellApplication {
        name = "rofi-pass";
        runtimeInputs = with pkgs; [
          cfg.package
          pass
          xclip
          findutils
          gnugrep
          gnused
          coreutils
        ];
        text = ''
          ${env}
          menu () { rofi -dmenu -i -no-auto-select -p "$1"; }
          field () {
            pass show "$entry" | grep -iE "^($1):" | head -n1 | sed 's/^[^:]*:[[:space:]]*//' || true
          }

          entry=$(cd "$PASSWORD_STORE_DIR" && find . -type f -name '*.gpg' \
            | sed -e 's|^\./||' -e 's/\.gpg$//' | sort | menu pass) || exit 0
          action=$(printf '%s\n' 'Copy password' 'Copy username' 'Copy URL' 'Copy OTP' \
            | menu "$entry") || exit 0

          case "$action" in
            'Copy password') pass show -c "$entry" ;;
            'Copy username') field 'username|user|login' | xclip -selection clipboard ;;
            'Copy URL')      field 'url|website|site' | xclip -selection clipboard ;;
            'Copy OTP')      pass otp -c "$entry" ;;
          esac
        '';
      };
    in
    {
      apps.launcher = lib.mkIf cfg.enableLauncher (lib.mkForce "${cfg.package}/bin/rofi -show drun");

      apps.passwordManager =
        lib.mkIf (cfg.enablePasswordManager && config.features.password-store.enable)
          (
            lib.mkForce (
              if config.globals.wayland then "${waylandPass}/bin/tessen" else "${x11Pass}/bin/rofi-pass"
            )
          );
    };

  home =
    { config, pkgs, ... }:
    let
      cfg = config.features.rofi;
    in
    lib.mkMerge [
      {
        programs.rofi = {
          enable = true;
          package = cfg.package;
          settings = mkSettings config // cfg.keybindings;
          theme = lib.mkIf config.features.theme.enable (mkTheme config);
        };
      }

      (lib.mkIf (cfg.enablePinentry && config.features.gnupg.enable) {
        services.gpg-agent.pinentry.package = lib.mkForce pkgs.pinentry-rofi;
      })
    ];
}
