{
  lib,
  mkFeature,
  mkElispConfig,
  ...
}:

let
  inherit (lib) mkOption types;
in
mkFeature {
  name = [
    "emacs"
    "keymaps"
  ];

  doc = {
    summary = "Prefix keymaps that make every Emacs feature's keys predictable";
    description = ''
      Every tessera feature makes its commands available in the same few
      places, so you can guess where a key lives before looking it up.
      Tessera's own keys all start with `C-c` followed by a letter, the only
      key sequences Emacs reserves for users, so no major or minor mode ever
      shadows them.
      This feature defines the shared keymaps and turns on which-key.

      | Keys | Purpose | Provided by |
      |------|---------|-------------|
      | `C-c a` | applications | this feature (`keys.app`) |
      | `C-c t` | toggles | this feature (`keys.toggle`) |
      | `C-c w` | side windows | emacs.window-management |
      | `M-g` | go to (Emacs' `goto-map`) | Emacs, extended |
      | `M-s` | search (Emacs' `search-map`) | Emacs, extended |
      | `C-x p` | project | Emacs |
      | `C-.`, `C-;` | act on the thing at point | emacs.completion |

      Commands that replace a built-in one keep its key, e.g. `C-x b` runs
      `consult-buffer` with the completion feature.

      - **Finding keys:** pause after a prefix such as `C-c` and which-key
        lists what follows; `C-h` after a prefix lists its keys with
        completion; `M-x describe-keymap` shows a whole keymap
      - **Toggles:** `C-c t` toggles modes. A lowercase key toggles a mode in
        the current buffer, the uppercase key its global variant

      | Key | Toggles |
      |-----|---------|
      | `f` / `F` | fill-column indicator |
      | `l` / `L` | line numbers |
      | `r` | read-only (buffer only) |
      | `v` / `V` | visual line mode |
      | `w` / `W` | whitespace display |

      **Rules for features**, which keep keys predictable as features are
      added:

      1. Built-ins first: replace a built-in command through a remap, and put
         commands that fit an Emacs prefix map there (`M-g` go to, `M-s`
         search, `C-x p` projects, `C-h` help)
      2. Everything else goes under `C-c` and a letter. Each letter is a
         domain; a feature gets its own letter only for a domain of its own,
         otherwise one key in `C-c a`, with a keymap of its own if it has
         several commands
      3. Packages define keymaps but never bind them; the feature's
         configuration binds them inside
         `(with-eval-after-load 'tessera-keymaps …)`, so nothing is bound when
         this feature is off
      4. Keys are Nix options: `key` for a single entry point, `keys.<name>`
         when there are several
      5. Every prefix has a label, shown by which-key
      6. Keys recommended upstream stay where they don't fit `C-c`, such as
         Embark's `C-.`

      A feature with one entry point declares a `key` option and binds its
      command in the applications map:

      ```nix
      options.key = lib.mkOption {
        type = lib.types.str;
        default = "e";
        description = "Key in `tessera-app-map`";
      };

      home = { config, ... }: {
        programs.emacs.extraConfig = '''
          (with-eval-after-load 'tessera-keymaps
            (keymap-set tessera-app-map "''${config.features.emacs.foo.key}" #'foo))
        ''';
      };
      ```

      A feature with several commands defines a keymap in its package and
      mounts it with a label, as window management does with `C-c w`:

      ```elisp
      (with-eval-after-load 'tessera-keymaps
        (keymap-set mode-specific-map "w" (cons "Windows" tessera-window-management-map)))
      ```
    '';
  };

  options = {
    keys = {
      app = mkOption {
        type = types.str;
        default = "a";
        description = "Key under `C-c` for `tessera-app-map`";
      };
      toggle = mkOption {
        type = types.str;
        default = "t";
        description = "Key under `C-c` for `tessera-toggle-map`";
      };
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
      cfg = config.features.emacs.keymaps;
    in
    lib.mkMerge [
      (mkElispConfig pkgs {
        name = "tessera-keymaps";
        summary = "Prefix keymaps shared by tessera features";

        config = ''
          (defvar-keymap tessera-app-map
            :doc "Prefix keymap for applications.
          Features bind their entry commands here.")

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
