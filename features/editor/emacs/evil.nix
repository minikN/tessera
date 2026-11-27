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
    "evil"
  ];

  doc = {
    summary = "Vim editing in Emacs with Evil";
    description = ''
      Enables Evil globally and extends its bindings to Emacs' built-in modes
      with Evil Collection. `gc` comments and uncomments code, and Evil
      Surround adds operators for changing, adding and deleting surrounding
      delimiters. Evil Org adds navigation and editing bindings to Org and Org
      Agenda buffers.

      - Undo and redo use `undo-fu`; an insert session can be undone in
        several steps
      - `j` and `k` move by screen lines, including outside
        `visual-line-mode`; operators still work on physical lines
      - Custom, Eshell, Git rebase and terminal buffers start in Emacs state,
        while Messages and dashboard buffers start in normal state
      - `C-j` and `C-k` navigate minibuffer history; with the completion
        feature, `C-r` searches it with Consult
      - Shifting with `>` and `<` uses Emacs' default `tab-width`
      - Winner is enabled for window layout undo and redo
      - `hideStateMessage` sets the default of
        `tessera-evil-hide-state-message`, which hides the insert and visual
        state messages, leaving their mode-line indicators. It can also be
        changed with `M-x customize`

      | Keys | Command |
      |------|---------|
      | `u`, `C-r` in normal state | undo, redo |
      | `C-u` in normal state | scroll up |
      | `C-M-u` | universal argument |
      | `Escape` | quit the current prompt or key sequence |
      | `C-g` in insert state | return to normal state |
      | `C-h` in insert state | delete backward, joining lines at the start |
      | `C-w u`, `C-w U` | undo, redo the window layout |

      Enable it with:

      ```nix
      features.emacs.evil = {
        enable = true;
        hideStateMessage = true;
      };
      ```
    '';
  };

  options = {
    hideStateMessage = mkOption {
      type = types.bool;
      default = false;
      description = "Default of `tessera-evil-hide-state-message`";
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
      cfg = config.features.emacs.evil;
    in
    mkElispConfig pkgs {
      name = "tessera-evil";
      summary = "Vim editing with Evil and Evil Collection";

      elispPackages =
        epkgs: with epkgs; [
          evil
          evil-collection
          evil-commentary
          evil-org
          evil-surround
          undo-fu
        ];

      config = # elisp
        ''
          (eval-when-compile
            (require 'evil)
            (require 'evil-collection)
            (require 'evil-commentary)
            (require 'evil-org-agenda)
            (require 'evil-surround)
            (require 'winner))
          (defvar evil-collection-company-use-tng)
          (defvar evil-collection-outline-bind-tab-p)
          (declare-function consult-history "consult")
          (declare-function evil-define-key* "evil-core")
          (declare-function evil-delete-backward-char-and-join "evil-commands")
          (declare-function evil-next-line "evil-commands")
          (declare-function evil-next-visual-line "evil-commands")
          (declare-function evil-normal-state "evil-states")
          (declare-function evil-previous-line "evil-commands")
          (declare-function evil-previous-visual-line "evil-commands")
          (declare-function evil-set-initial-state "evil-core")
          (declare-function org-metadown "org")
          (declare-function org-metaup "org")
          (declare-function org-next-visible-heading "org")
          (declare-function org-previous-visible-heading "org")
          (declare-function winner-redo "winner")
          (declare-function winner-undo "winner")

          (setq evil-want-keybinding nil
                evil-want-integration t
                evil-want-C-u-scroll t
                evil-want-C-i-jump nil
                evil-respect-visual-line-mode t
                evil-undo-system 'undo-fu
                evil-want-fine-undo t
                evil-shift-width tab-width
                evil-collection-company-use-tng nil
                evil-collection-outline-bind-tab-p nil)
          (require 'evil)
          (require 'evil-collection)
          (require 'evil-commentary)
          (require 'evil-org)
          (require 'evil-surround)
          (require 'winner)
          (setq evil-collection-mode-list
                (remove 'lispy evil-collection-mode-list))

          (defgroup tessera-evil nil
            "Vim editing with Evil."
            :group 'tessera
            :prefix "tessera-evil-")

          (defvar tessera-evil--state-messages nil
            "State messages hidden by `tessera-evil-hide-state-message'.")

          (defun tessera-evil--set-hide-state-message (symbol value)
            "Set SYMBOL to VALUE and hide or restore Evil's state messages."
            (set-default-toplevel-value symbol value)
            (if value
                (progn
                  (unless tessera-evil--state-messages
                    (setq tessera-evil--state-messages
                          (cons evil-insert-state-message evil-visual-state-message)))
                  (setq evil-insert-state-message nil
                        evil-visual-state-message nil))
              (when tessera-evil--state-messages
                (setq evil-insert-state-message (car tessera-evil--state-messages)
                      evil-visual-state-message (cdr tessera-evil--state-messages)
                      tessera-evil--state-messages nil))))

          (defcustom tessera-evil-hide-state-message ${if cfg.hideStateMessage then "t" else "nil"}
            "Non-nil means hide insert and visual state messages.
            The mode line continues to indicate Evil's state.  Disabling this
            option restores the messages that were hidden."
            :type 'boolean
            :group 'tessera-evil
            :initialize #'custom-initialize-default
            :set #'tessera-evil--set-hide-state-message)
          (tessera-evil--set-hide-state-message
           'tessera-evil-hide-state-message tessera-evil-hide-state-message)

          (defun tessera-evil--set-initial-states (&rest _)
            "Set the initial states of modes, overriding Evil Collection's."
            (dolist (mode '(Custom-mode eshell-mode git-rebase-mode term-mode))
              (evil-set-initial-state mode 'emacs))
            (dolist (mode '(messages-buffer-mode dashboard-mode))
              (evil-set-initial-state mode 'normal)))
          (tessera-evil--set-initial-states)
          ;; Evil Collection sets its initial states when each mode is loaded
          (add-hook 'evil-collection-setup-hook #'tessera-evil--set-initial-states)

          (keymap-global-set "C-M-u" #'universal-argument)
          (keymap-global-set "<escape>" #'keyboard-escape-quit)
          (keymap-global-set "<lwindow-j>" #'ignore)
          (keymap-global-set "<lwindow-k>" #'ignore)
          (keymap-set minibuffer-mode-map "C-j" #'next-line-or-history-element)
          (keymap-set minibuffer-mode-map "C-k" #'previous-line-or-history-element)
          ${lib.optionalString config.features.emacs.completion.enable ''
            (keymap-set minibuffer-mode-map "C-r" #'consult-history)
          ''}
          (keymap-set evil-insert-state-map "C-g" #'evil-normal-state)
          (keymap-set evil-insert-state-map "C-h" #'evil-delete-backward-char-and-join)
          (keymap-set evil-motion-state-map "j" #'evil-next-visual-line)
          (keymap-set evil-motion-state-map "k" #'evil-previous-visual-line)
          (keymap-set evil-operator-state-map "j" #'evil-next-line)
          (keymap-set evil-operator-state-map "k" #'evil-previous-line)
          (keymap-set evil-normal-state-map "u" #'undo-fu-only-undo)
          (keymap-set evil-normal-state-map "C-r" #'undo-fu-only-redo)

          (evil-define-key '(normal insert visual) org-mode-map
            (kbd "C-j") #'org-next-visible-heading)
          (evil-define-key '(normal insert visual) org-mode-map
            (kbd "C-k") #'org-previous-visible-heading)
          (evil-define-key '(normal insert visual) org-mode-map
            (kbd "M-j") #'org-metadown)
          (evil-define-key '(normal insert visual) org-mode-map
            (kbd "M-k") #'org-metaup)

          (add-hook 'org-mode-hook #'evil-org-mode)
          (add-hook 'org-agenda-mode-hook #'evil-org-mode)
          (add-hook 'evil-org-mode-hook
                    (lambda ()
                      (evil-org-set-key-theme
                       '(navigation todo insert textobjects additional))))
          (require 'evil-org-agenda)
          (evil-org-agenda-set-keys)

          (keymap-set evil-window-map "u" #'winner-undo)
          (keymap-set evil-window-map "U" #'winner-redo)
          (winner-mode 1)

          (evil-mode 1)
          (evil-collection-init)
          (evil-commentary-mode 1)
          (global-evil-surround-mode 1)
        '';
    };
}
