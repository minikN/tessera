{ lib, mkFeature, ... }:

mkFeature {
  name = "gtk";
  platforms = [
    "home"
    "nixos"
  ];

  doc = {
    summary = "GTK theme, icons and cursor that follow the light/dark polarity";
    description = ''
      Styles GTK 3 and GTK 4 applications with the set theme. If a light and dark
      variant are given, it choose the correct one based on the `polarity` in the
      `theme` feature.
    '';
  };

  options =
    { config, pkgs, ... }:
    let
      inherit (lib) mkOption types;
      polarity = if config.features.theme.enable then config.features.theme.polarity else "light";
      themeModule = types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Theme name";
          };
          package = mkOption {
            type = types.package;
            description = "Theme package";
          };
        };
      };
    in
    {
      defaultThemes = mkOption {
        type = types.attrsOf themeModule;
        description = "Built-in light/dark GTK themes";
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
        description = "Active GTK theme";
        defaultText = lib.literalExpression "config.features.gtk.defaultThemes.\${config.features.theme.polarity}";
        default = config.features.gtk.defaultThemes.${polarity};
      };

      iconTheme = mkOption {
        type = themeModule;
        description = "Icon theme";
        defaultText = lib.literalExpression ''{ name = "Adwaita"; package = pkgs.adwaita-icon-theme; }'';
        default = {
          name = "Adwaita";
          package = pkgs.adwaita-icon-theme;
        };
      };

      cursorTheme = mkOption {
        type = themeModule;
        description = "Cursor theme";
        defaultText = lib.literalMD ''
          Either `Bibata-Modern-Classic` (dark) or `Bibata-Modern-Ice` (light) depending on
          the `polarity` set in the `theme` feature.
        '';
        default = {
          name = "Bibata-Modern-${if polarity == "dark" then "Classic" else "Ice"}";
          package = pkgs.bibata-cursors;
        };
      };

      cursorSize = mkOption {
        type = types.int;
        default = 24;
        description = "Cursor size (px)";
      };

      extraCss = mkOption {
        type = types.lines;
        default = "";
        description = "Extra CSS for gtk3 + gtk4";
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
        description = "Extra settings.ini entries for gtk3 + gtk4";
      };
    };

  nixos = _: { programs.dconf.enable = true; };

  home =
    { config, ... }:
    let
      cfg = config.features.gtk;
    in
    {
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
