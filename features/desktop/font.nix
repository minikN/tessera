{ lib, mkFeature, ... }:

mkFeature {
  name = "font";

  doc = {
    summary = "Default fonts for desktop applications and terminals.";
    description = ''
      Installs four fonts and makes them the fontconfig defaults: `monospace`
      for terminals and editors, `serif`, `sans` (the serif font unless set)
      and `unicode` for emoji. A few fallback fonts (DejaVu, Unifont, Font
      Awesome) are installed too.

      - **Shared with other features:** terminal, editor and launcher
        features (e.g. ghostty, Emacs, rofi, choose-gui) use these fonts
        while this feature is enabled. Without it, they keep their own
        default fonts.

      ```nix
      features.font = {
        enable = true;
        fonts.monospace = { name = "Menlo"; size = 13; };
      };
      ```
    '';
  };

  options = { config, pkgs, ... }:
    let
      inherit (lib) mkOption types;
      fontModule = types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Font family name.";
          };
          package = mkOption {
            type = types.nullOr types.package;
            default = null;
            description = "Font package; null to skip install (e.g. OS-shipped).";
          };
          size = mkOption {
            type = types.int;
            default = 11;
            description = "Size in points.";
          };
        };
      };
    in
    {
      fonts = {
        monospace = mkOption {
          type = fontModule;
          description = "Monospace font.";
          defaultText = lib.literalExpression ''{ name = "Iosevka Nerd Font Mono"; package = pkgs.nerd-fonts.iosevka; size = 15; }'';
          default = {
            name = "Iosevka Nerd Font Mono";
            package = pkgs.nerd-fonts.iosevka;
            size = 15;
          };
        };
        serif = mkOption {
          type = fontModule;
          description = "Serif font.";
          defaultText = lib.literalExpression ''{ name = "IBM Plex Sans"; package = pkgs.ibm-plex; size = 11; }'';
          default = {
            name = "IBM Plex Sans";
            package = pkgs.ibm-plex;
            size = 11;
          };
        };
        sans = mkOption {
          type = fontModule;
          description = "Sans-serif font.";
          defaultText = lib.literalExpression "config.features.font.fonts.serif";
          default = config.features.font.fonts.serif;
        };
        unicode = mkOption {
          type = fontModule;
          description = "Unicode / emoji font.";
          ## On darwin use Apple Color Emoji; noto-fonts-color-emoji's
          ## afdko build is broken on aarch64-darwin.
          defaultText = lib.literalMD "Apple Color Emoji (shipped with macOS) on macOS, Noto Color Emoji (`pkgs.noto-fonts-color-emoji`) on Linux; size 11";
          default =
            if config.globals.platform == "darwin"
            then { name = "Apple Color Emoji"; package = null; size = 11; }
            else { name = "Noto Color Emoji"; package = pkgs.noto-fonts-color-emoji; size = 11; };
        };
      };
    };

  home = { config, lib, pkgs, ... }:
    let
      cfg = config.features.font.fonts;
    in
    {
      fonts.fontconfig = {
        enable = true;
        defaultFonts = {
          monospace = [ cfg.monospace.name ];
          serif = [ cfg.serif.name ];
          sansSerif = [ cfg.sans.name ];
          emoji = [ cfg.unicode.name ];
        };
      };

      home.packages = lib.filter (p: p != null) (with pkgs; [
        cfg.monospace.package
        cfg.serif.package
        cfg.sans.package
        cfg.unicode.package
        dejavu_fonts
        unifont
        font-awesome
      ]);
    };
}
