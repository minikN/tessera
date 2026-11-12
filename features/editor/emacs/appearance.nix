{
  lib,
  mkFeature,
  mkElispConfig,
  ...
}:

mkFeature {
  name = [
    "emacs"
    "appearance"
  ];

  doc = {
    summary = "Changes Emacs' appearance to a modern, clean look";
    description = ''
      Decides how Emacs looks. Frames lose their bars, text uses the font
      feature's fonts, windows and their mode lines get some room, and the
      colours come from the Modus themes, either as they are or in the colours
      of the theme feature that ghostty, sway and rofi use too.

      - No menu bar, tool bar, scroll bars or splash screen and an empty scratch buffer
      - text in the `font` feature's monospace font and emoji in its emoji font.
        (requires the `font` feature to be enabled)
      - `margin` pixels of space around the frame and between side-by-side windows.
         Fringes `fringes` pixels wide
      - paddings for the mode line, header line, tab bar and echo area
      - Italic and bold for comments, keywords and other constructs, fixed-pitch
        code in proportional text

      If the `theme` feature is enabled, Emacs will be colored using the chosen
      scheme in the theme feature. `modus-themes` is used as a base theme with
      the custom palette on top. If the `default` scheme (in theme.nix) is used,
      this functionality is disabled as the default scheme already uses the
      modus color palette.
      The functionality can also be disabled by setting `useScheme` to `false`.

      If a theme is saved with `M-x customize-themes` it'll take precedence over
      the nix setting.

      | Colour | Used for |
      |--------|----------|
      | `base00`, `base01`, `base02` | background, line numbers and popups, selection |
      | `base03` | comments, bright black in terminals |
      | `base04`, `base05`, `base06` | dim text, text and operators, alternative text |
      | `base07` | bright white in terminals |
      | `base08` | red, variables |
      | `base09` | constants and numbers |
      | `base0A` | yellow, types |
      | `base0B` | green, strings |
      | `base0C` | cyan, builtins, regular expressions |
      | `base0D` | blue, functions |
      | `base0E` | magenta, keywords |
      | `base0F` | preprocessor directives |

      ```nix
      features.emacs.appearance = {
        enable = true;
        margin = 12;
        headerLineAsModeLine = false;
      };
      features.theme = {
        enable = true;
        scheme = "monokai-pro";
        polarity = "dark";
      };
      ```
    '';
    darwin = ''
      - Transparent title bar, with light or dark text following the
        enabled theme
    '';
  };

  options =
    { config, ... }:
    {
      useScheme = lib.mkOption {
        type = lib.types.bool;
        default =
          let
            inherit (config.features.theme) scheme;
            modus = (import ../../../schemes).default;
          in
          scheme.light != modus.light || scheme.dark != modus.dark;
        defaultText = lib.literalMD "`true`, unless `features.theme.scheme` is `default`";
        description = "Whether to build the Emacs theme from `features.theme.scheme`; otherwise the Modus theme of `features.theme.polarity` is used as it is";
      };

      margin = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 8;
        description = "Space in pixels around the frame and between side-by-side windows, the default of `tessera-appearance-margin`";
      };

      fringes = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 8;
        description = "Width in pixels of the left and right fringes, the default of `tessera-appearance-fringes`";
      };

      padding = {
        modeLine = lib.mkOption {
          type = lib.types.ints.unsigned;
          default = 4;
          description = "Padding in pixels around the mode line, the default of `tessera-appearance-mode-line-padding`";
        };
        headerLine = lib.mkOption {
          type = lib.types.ints.unsigned;
          default = 4;
          description = "Padding in pixels around the header line, the default of `tessera-appearance-header-line-padding`";
        };
        tabBar = lib.mkOption {
          type = lib.types.ints.unsigned;
          default = 4;
          description = "Padding in pixels around the tab bar, the default of `tessera-appearance-tab-bar-padding`";
        };
        echoArea = lib.mkOption {
          type = lib.types.ints.unsigned;
          default = config.features.emacs.appearance.margin;
          defaultText = lib.literalExpression "margin";
          description = "Space in pixels between the windows and the echo area, and between stacked windows, the default of `tessera-appearance-echo-area-padding`";
        };
      };

      headerLineAsModeLine = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to show the mode line at the top of windows, in the header line, the default of `tessera-appearance-header-line-as-mode-line`";
      };
    };

  home =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.features.emacs.appearance;
      inherit (config.features) font theme;
      emacsTheme =
        if cfg.useScheme then
          "tessera"
        else if theme.polarity == "dark" then
          "modus-vivendi"
        else
          "modus-operandi";
      isDarwin = config.globals.platform == "darwin";
      modusColors =
        let
          syntax = lib.mapAttrs (_: base: theme.colors.withHashtag.${base}) theme.scheme.syntax;
        in
        with theme.colors.withHashtag;
        {
          bg-main = base00;
          bg-dim = base01;
          bg-active = base02;
          fg-term-black-bright = base03;
          bg-term-black-bright = base03;
          fg-dim = base04;
          fg-main = base05;
          fg-alt = base06;
          fg-term-white-bright = base07;
          bg-term-white-bright = base07;
          red = base08;
          yellow = base0A;
          green = base0B;
          cyan = base0C;
          blue = base0D;
          magenta = base0E;
          comment = syntax.comment;
          docstring = syntax.docstring;
          variable = syntax.variable;
          variable-use = syntax.variable;
          constant = syntax.constant;
          number = syntax.number;
          type = syntax.type;
          string = syntax.string;
          builtin = syntax.builtin;
          rx-construct = syntax.regexp;
          rx-backslash = syntax.regexp;
          fnname = syntax.function;
          fnname-call = syntax.function;
          keyword = syntax.keyword;
          operator = syntax.operator;
          preprocessor = syntax.preprocessor;
        };
      themeDir = pkgs.writeTextDir "tessera-theme.el" ''
        ;;; tessera-theme.el --- Modus theme in the tessera colours -*- lexical-binding: t -*-

        (require 'modus-themes)

        (defconst tessera-palette
          (modus-themes-generate-palette
           '(${
             lib.concatStringsSep "\n     " (
               lib.mapAttrsToList (name: value: ''(${name} "${value}")'') modusColors
             )
           }))
          "Palette of the `tessera' theme, generated from the base16 scheme.")

        (modus-themes-theme
         'tessera
         'tessera
         "Modus theme in the tessera colours."
         '${theme.polarity}
         'tessera-palette
         nil
         nil)
      '';
    in
    lib.mkMerge [
      (mkElispConfig pkgs {
        name = "tessera-appearance";
        summary = "Clean frames, fonts, spacing and a Modus theme";
        elispPackages = epkgs: [ epkgs.modus-themes ];

        earlyInit = ''
          ${lib.optionalString (
            theme.enable && cfg.useScheme
          ) ''(add-to-list 'custom-theme-load-path "${themeDir}")''}
          (push '(menu-bar-lines . 0) default-frame-alist)
          (push '(tool-bar-lines . 0) default-frame-alist)
          (push '(vertical-scroll-bars) default-frame-alist)
          (push '(horizontal-scroll-bars) default-frame-alist)
          (setq menu-bar-mode nil
                tool-bar-mode nil
                scroll-bar-mode nil
                inhibit-startup-screen t
                initial-scratch-message nil)
          ${lib.optionalString font.enable ''
            (push '(font . "${font.fonts.monospace.name}-${toString font.fonts.monospace.size}")
                  default-frame-alist)
          ''}
          (push '(internal-border-width . ${toString cfg.margin}) default-frame-alist)
          (push '(left-fringe . ${toString cfg.fringes}) default-frame-alist)
          (push '(right-fringe . ${toString cfg.fringes}) default-frame-alist)
          ${lib.optionalString isDarwin ''
            (push '(ns-transparent-titlebar . t) default-frame-alist)
          ''}
        '';

        config = ''
          (require 'modus-themes)

          (defgroup tessera-appearance nil
            "Margins, fringes and paddings of Emacs frames and windows."
            :group 'tessera
            :prefix "tessera-appearance-")

          (defun tessera-appearance--set (symbol value)
            "Set SYMBOL to VALUE and apply the appearance settings."
            (set-default-toplevel-value symbol value)
            (tessera-appearance--apply))

          (defcustom tessera-appearance-margin ${toString cfg.margin}
            "Space in pixels around the frame and between side-by-side windows."
            :type 'natnum
            :initialize #'custom-initialize-default
            :set #'tessera-appearance--set)

          (defcustom tessera-appearance-fringes ${toString cfg.fringes}
            "Width in pixels of the left and right fringes."
            :type 'natnum
            :initialize #'custom-initialize-default
            :set #'tessera-appearance--set)

          (defcustom tessera-appearance-mode-line-padding ${toString cfg.padding.modeLine}
            "Padding in pixels around the mode line."
            :type 'natnum
            :initialize #'custom-initialize-default
            :set #'tessera-appearance--set)

          (defcustom tessera-appearance-header-line-padding ${toString cfg.padding.headerLine}
            "Padding in pixels around the header line."
            :type 'natnum
            :initialize #'custom-initialize-default
            :set #'tessera-appearance--set)

          (defcustom tessera-appearance-tab-bar-padding ${toString cfg.padding.tabBar}
            "Padding in pixels around the tab bar."
            :type 'natnum
            :initialize #'custom-initialize-default
            :set #'tessera-appearance--set)

          (defcustom tessera-appearance-echo-area-padding ${toString cfg.padding.echoArea}
            "Space in pixels between the windows and the echo area, and between stacked windows."
            :type 'natnum
            :initialize #'custom-initialize-default
            :set #'tessera-appearance--set)

          (defcustom tessera-appearance-header-line-as-mode-line ${
            if cfg.headerLineAsModeLine then "t" else "nil"
          }
            "Non-nil means show the mode line at the top of windows, in the header line."
            :type 'boolean
            :initialize #'custom-initialize-default
            :set #'tessera-appearance--set)

          (defvar tessera-appearance--mode-line-format nil
            "The default `mode-line-format' while it is shown in the header line.")

          (defun tessera-appearance--move-mode-line (to-header-line)
            "Show the mode line in the header line if TO-HEADER-LINE, else at the bottom."
            (cond
             ((and to-header-line (not tessera-appearance--mode-line-format))
              (setq tessera-appearance--mode-line-format (default-value 'mode-line-format))
              (setq-default header-line-format tessera-appearance--mode-line-format
                            mode-line-format nil))
             ((and (not to-header-line) tessera-appearance--mode-line-format)
              (setq-default mode-line-format tessera-appearance--mode-line-format
                            header-line-format nil)
              (setq tessera-appearance--mode-line-format nil))))

          (defun tessera-appearance--apply ()
            "Apply margin, fringes, paddings and mode line position."
            (modify-all-frames-parameters
             `((internal-border-width . ,tessera-appearance-margin)))
            ;; Bottom dividers also separate the lowest windows from the echo area
            (setq window-divider-default-right-width tessera-appearance-margin
                  window-divider-default-bottom-width tessera-appearance-echo-area-padding
                  window-divider-default-places t)
            (window-divider-mode (if (> (+ tessera-appearance-margin tessera-appearance-echo-area-padding) 0)
                                     1 -1))
            (fringe-mode tessera-appearance-fringes)

            ;; Flat boxes take the face's background, so they work with any theme
            (pcase-dolist (`(,face . ,width)
                           `((mode-line . ,tessera-appearance-mode-line-padding)
                             (mode-line-inactive . ,tessera-appearance-mode-line-padding)
                             (header-line . ,tessera-appearance-header-line-padding)
                             (tab-bar . ,tessera-appearance-tab-bar-padding)))
              (face-spec-set face (and (> width 0)
                                       `((t :box (:line-width ,width :style flat-button))))))
            (tessera-appearance--move-mode-line tessera-appearance-header-line-as-mode-line))

          (defun tessera-appearance--hide-window-dividers (&rest _)
            "Draw window dividers in the background colour of the Modus theme in use."
            (let ((bg (modus-themes-with-colors bg-main)))
              (dolist (face '(window-divider window-divider-first-pixel
                              window-divider-last-pixel vertical-border))
                (face-spec-set face (and bg `((t :foreground ,bg)))))))

          (add-hook 'enable-theme-functions #'tessera-appearance--hide-window-dividers)
          (tessera-appearance--apply)

          (setopt modus-themes-italic-constructs t
                  modus-themes-bold-constructs t
                  modus-themes-mixed-fonts t
                  modus-themes-common-palette-overrides '((fringe unspecified)))
          ;; Level 4 also colours function calls, properties and operators.
          (with-eval-after-load 'treesit
            (setopt treesit-font-lock-level 4))
          ${lib.optionalString font.enable ''
            (defun tessera-appearance--set-emoji-font ()
              (when (display-graphic-p)
                (set-fontset-font t 'emoji (font-spec :family "${font.fonts.unicode.name}"))))
            (tessera-appearance--set-emoji-font)
            (add-hook 'server-after-make-frame-hook #'tessera-appearance--set-emoji-font)
          ''}
          ${lib.optionalString isDarwin ''
            (defun tessera-appearance--set-ns-appearance (theme)
              "Give the title bar the background mode of THEME."
              (when-let* ((mode (plist-get (get theme 'theme-properties) :background-mode)))
                (modify-all-frames-parameters `((ns-appearance . ,mode)))))
            (add-hook 'enable-theme-functions #'tessera-appearance--set-ns-appearance)
          ''}
        '';
      })

      {
        programs.emacs.extraConfig = lib.optionalString theme.enable ''
          (modus-themes-activate '${emacsTheme})
          (unless custom-enabled-themes
            (enable-theme '${emacsTheme}))
        '';
      }
    ];
}
