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
      | `C-c c` | code | this feature (`keys.code`), filled by emacs.eglot and language features |
      | `C-c t` | toggles | this feature (`keys.toggle`) |
      | `C-c w` | side windows | emacs.window-management |
      | `M-g` | go to (Emacs' `goto-map`) | Emacs, extended |
      | `M-s` | search (Emacs' `search-map`) | Emacs, extended |
      | `C-x p` | project | Emacs |
      | `C-.`, `C-;` | act on the thing at point | emacs.completion |

      Commands that replace a built-in one keep its key, e.g. `C-x b` runs
      `consult-buffer` with the completion feature.

      - Pause after a prefix such as `C-c` and which-key
        lists what follows; `C-h` after a prefix lists its keys with
        completion; `M-x describe-keymap` shows a whole keymap
      - While which-key's popup is open, `C-h` leads to its commands: `C-h c`
        switches between the keys' descriptions and the commands they run,
        for every popup until you switch back, `C-h d` adds docstrings,
        `C-h n` and `C-h p` page and `C-h h` lists the keys with completion
      - `C-c t` toggles modes. A lowercase key toggles a mode in the current
         buffer, the uppercase key its global variant

      | Key | Toggles |
      |-----|---------|
      | `f` / `F` | fill-column indicator |
      | `l` / `L` | line numbers |
      | `r` | read-only (buffer only) |
      | `v` / `V` | visual line mode |
      | `w` / `W` | whitespace display |
    '';
  };

  options = {
    keys = {
      app = mkOption {
        type = types.str;
        default = "a";
        description = "Key under `C-c` for `tessera-app-map`";
      };
      code = mkOption {
        type = types.str;
        default = "c";
        description = "Key under `C-c` for `tessera-code-map`";
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

        config = # elisp
          ''
            (defgroup tessera-keymaps nil
              "Prefix keymaps shared by tessera features."
              :group 'tessera)

            (defcustom tessera-keymaps-which-key-commands nil
              "Non-nil means which-key shows the commands keys run, not their descriptions.
            Prefixes keep their descriptions.  `C-h c' toggles it in which-key's popup."
              :type 'boolean
              :group 'tessera-keymaps)

            (defvar which-key-max-description-length)

            (defun tessera-keymaps--which-key-commands (format unformatted &rest args)
              "Call FORMAT, `which-key--format-and-replace', maybe with commands.
            UNFORMATTED is its list of (KEY . DESCRIPTION).  If
            `tessera-keymaps-which-key-commands' is non-nil, a description becomes
            the name of the command KEY runs, untruncated; prefixes keep theirs."
              (if (not tessera-keymaps-which-key-commands)
                  (apply format unformatted args)
                (let ((which-key-max-description-length nil))
                  (apply format
                         (mapcar (pcase-lambda (`(,key . ,description))
                                   (let ((command (ignore-errors (key-binding (kbd key)))))
                                     (cons key (if (and command (symbolp command))
                                                   (symbol-name command)
                                                 description))))
                                 unformatted)
                         args))))

            (defun tessera-keymaps-which-key-toggle-commands (&optional _key)
              "Toggle between descriptions and commands in which-key's popup.
            See `tessera-keymaps-which-key-commands'."
              (interactive)
              (setq tessera-keymaps-which-key-commands (not tessera-keymaps-which-key-commands))
              (when (which-key--popup-showing-p)
                (which-key-reload-key-sequence)
                (which-key--create-buffer-and-show (which-key--current-prefix))))

            (defvar-keymap tessera-app-map
              :doc "Prefix keymap for applications.
            Features bind their entry commands here.")

            (defvar-keymap tessera-toggle-map
              :doc "Prefix keymap for toggling modes.
            Lowercase keys toggle a buffer-local mode, uppercase keys its global variant."
              "f" '("fill column" . display-fill-column-indicator-mode)
              "F" '("fill column (global)" . global-display-fill-column-indicator-mode)
              "l" '("line numbers" . display-line-numbers-mode)
              "L" '("line numbers (global)" . global-display-line-numbers-mode)
              "r" '("read-only" . read-only-mode)
              "v" '("visual line mode" . visual-line-mode)
              "V" '("visual line mode (global)" . global-visual-line-mode)
              "w" '("whitespace display" . whitespace-mode)
              "W" '("whitespace display (global)" . global-whitespace-mode))

            (defvar tessera-code-package-maps nil
              "Alist of (PREDICATE . KEYMAP) behind `p' in `tessera-code-map'.
            PREDICATE is called without arguments in the current buffer; the
            keymaps of all predicates returning non-nil are combined.")

            (defun tessera-keymaps--package-map (_binding)
              "Return the labelled package keymap for the current buffer, or nil."
              (when-let* ((maps (seq-keep (pcase-lambda (`(,predicate . ,map))
                                            (and (funcall predicate) map))
                                          tessera-code-package-maps)))
                (cons "packages" (make-composed-keymap maps))))

            (defvar-keymap tessera-code-map
              :doc "Prefix keymap for working on code.
            Eglot binds its commands here in the buffers it manages, language
            features their utilities under `u' in their major modes, and `p'
            leads to the package commands of the project at hand, see
            `tessera-code-package-maps'."
              "p" '(menu-item "packages" nil :filter tessera-keymaps--package-map))
          '';
      })

      {
        programs.emacs.extraConfig = # elisp
          ''
            (keymap-set mode-specific-map "${cfg.keys.app}" (cons "applications" tessera-app-map))
            (keymap-set mode-specific-map "${cfg.keys.code}" (cons "code" tessera-code-map))
            ;; Hide keys whose filter finds nothing, e.g. `C-c c p' outside a package
            (with-eval-after-load 'which-key
              (add-to-list 'which-key-replacement-alist '((nil . "\\`nil\\'") . t))
              (advice-add 'which-key--format-and-replace :around #'tessera-keymaps--which-key-commands)
              (keymap-set which-key-C-h-map "C-c" #'tessera-keymaps-which-key-toggle-commands)
              (keymap-set which-key-C-h-map "c" #'tessera-keymaps-which-key-toggle-commands)
              (setopt which-key-min-column-description-width 30)
              (setq which-key-C-h-map-prompt
                    (string-replace "toggle-docstrings,"
                                    (concat "toggle-docstrings, \\[tessera-keymaps-which-key-toggle-commands]"
                                            which-key-separator "toggle-commands,")
                                    which-key-C-h-map-prompt)))
            (keymap-set mode-specific-map "${cfg.keys.toggle}" (cons "toggles" tessera-toggle-map))
            ;; After every feature set `prefix-help-command' (e.g. Embark's), so
            ;; which-key takes over `C-h' in its popup and falls back to it
            (add-hook 'after-init-hook #'which-key-mode)
          '';
      }
    ];
}
