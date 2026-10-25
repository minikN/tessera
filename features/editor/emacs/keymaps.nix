{ lib, mkFeature, mkElispConfig, ... }:

let
  inherit (lib) mkOption types;
in
mkFeature {
  name = [ "emacs" "keymaps" ];

  options = {
    keys = {
      app = mkOption {
        type = types.str;
        default = "a";
        description = "Key under `C-c` for `tessera-app-map`.";
      };
      toggle = mkOption {
        type = types.str;
        default = "t";
        description = "Key under `C-c` for `tessera-toggle-map`.";
      };
    };
  };

  home = { config, lib, pkgs, ... }:
    let
      cfg = config.features.emacs.keymaps;
    in
    lib.mkMerge [
      (mkElispConfig pkgs {
        name = "tessera-keymaps";
        summary = "Prefix keymaps shared by tessera features";
        manual = ./keymaps.org;

        config = ''
          (defvar-keymap tessera-app-map
            :doc "Prefix keymap for applications.
          Features bind their entry commands here; see Info node `(tessera-keymaps)'.")

          (defvar-keymap tessera-toggle-map
            :doc "Prefix keymap for toggling modes.
          Lowercase keys toggle a buffer-local mode, uppercase keys its global variant."
            "f" #'display-fill-column-indicator-mode
            "F" #'global-display-fill-column-indicator-mode
            "l" #'display-line-numbers-mode
            "L" #'global-display-line-numbers-mode
            "r" #'read-only-mode
            "v" #'visual-line-mode
            "V" #'global-visual-line-mode
            "w" #'whitespace-mode
            "W" #'global-whitespace-mode)
        '';
      })

      {
        programs.emacs.extraConfig = ''
          (keymap-set mode-specific-map "${cfg.keys.app}" (cons "Applications" tessera-app-map))
          (keymap-set mode-specific-map "${cfg.keys.toggle}" (cons "Toggles" tessera-toggle-map))
          (which-key-mode 1)
        '';
      }
    ];
}
