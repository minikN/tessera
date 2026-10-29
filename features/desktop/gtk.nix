{ lib, mkFeature, ... }:

mkFeature {
  name = "gtk";
  platforms = [
    "home"
    "nixos"
  ];

  doc = {
    summary = "GTK theme, icons and cursor that follow the light/dark polarity.";
    description = ''
      Styles GTK 3 and GTK 4 applications: the theme (adw-gtk3, light or dark
      following `features.theme.polarity`), the icon theme (Adwaita) and the
      cursor (Bibata, `cursorSize` pixels). It also installs dconf and GNOME
      Tweaks.

      - **Tweaks:** `extraCss` and `extraConfig` (`settings.ini` entries) apply
        to both GTK versions.
    '';
  };

  options =
    { config, pkgs, ... }:
    let
      inherit (lib) mkOption types;
      themeModule = types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Theme name.";
          };
          package = mkOption {
            type = types.package;
            description = "Theme package.";
          };
        };
      };
    in
    {
      defaultThemes = mkOption {
        type = types.attrsOf themeModule;
        description = "Built-in light/dark GTK themes (consumed by `theme` default).";
        defaultText = lib.literalExpression ''{ light = { name = "adw-gtk3"; package = pkgs.adw-gtk3; }; dark = { name = "adw-gtk3-dark"; package = pkgs.adw-gtk3; }; }'';
        default = {
          light = {
            name = "adw-gtk3";
            package = pkgs.adw-gtk3;
          };
          dark = {
            name = "adw-gtk3-dark";
            package = pkgs.adw-gtk3;
          };
        };
      };

      theme = mkOption {
        type = themeModule;
        description = "Active GTK theme; defaults from `defaultThemes` by `theme.polarity`.";
        defaultText = lib.literalExpression "config.features.gtk.defaultThemes.\${config.features.theme.polarity}";
        default = config.features.gtk.defaultThemes.${config.features.theme.polarity};
      };

      iconTheme = mkOption {
        type = themeModule;
        description = "Icon theme.";
        defaultText = lib.literalExpression ''{ name = "Adwaita"; package = pkgs.adwaita-icon-theme; }'';
        default = {
          name = "Adwaita";
          package = pkgs.adwaita-icon-theme;
        };
      };

      cursorTheme = mkOption {
        type = themeModule;
        description = "Cursor theme.";
        defaultText = lib.literalMD "`Bibata-Modern-Classic` (dark polarity) or `Bibata-Modern-Ice` (light) from `pkgs.bibata-cursors`";
        default = {
          name = "Bibata-Modern-${if config.features.theme.polarity == "dark" then "Classic" else "Ice"}";
          package = pkgs.bibata-cursors;
        };
      };

      cursorSize = mkOption {
        type = types.int;
        default = 24;
        description = "Cursor size (px).";
      };

      extraCss = mkOption {
        type = types.lines;
        default = "";
        description = "Extra CSS for gtk3 + gtk4.";
      };

      extraConfig = mkOption {
        type =
          with types;
          attrsOf (oneOf [
            bool
            int
            str
          ]);
        default = { };
        description = "Extra settings.ini entries for gtk3 + gtk4.";
      };
    };

  home =
    { config, pkgs, ... }:
    let
      cfg = config.features.gtk;
    in
    {
      home.packages = with pkgs; [
        dconf
        gnome-tweaks
      ];

      home.pointerCursor = lib.mkDefault {
        enable = true;
        inherit (cfg.cursorTheme) name package;
        size = cfg.cursorSize;
        gtk.enable = true;
      };

      gtk = {
        enable = true;
        inherit (cfg) theme iconTheme cursorTheme;
      }
      // lib.genAttrs [ "gtk3" "gtk4" ] (
        lib.const {
          inherit (cfg) extraCss extraConfig;
        }
      );
    };
}
