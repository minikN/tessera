{
  lib,
  mkFeature,
  mkElispConfig,
  ...
}:

let
  inherit (lib) mkDefault mkOption types;

  windowType = types.submodule {
    options = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to include this window";
      };
      side = mkOption {
        type = types.enum [
          "left"
          "right"
          "top"
          "bottom"
        ];
        description = "Frame side of the window";
      };
      slot = mkOption {
        type = types.int;
        default = 0;
        description = "Position among windows on the same side; negative is left/above, positive right/below";
      };
      size = mkOption {
        type = types.number;
        description = "Width (left/right) or height (top/bottom): a fraction of the frame, or columns/lines";
      };
      names = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Regexps matched against buffer names";
      };
      modes = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Major modes; modes derived from them match too";
      };
      key = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Key selecting this window in `tessera-window-management-map`";
      };
    };
  };
in
mkFeature {
  name = [
    "emacs"
    "window-management"
  ];

  doc = {
    summary = "Predictable buffer display in side windows";
    description = ''
      Where Emacs shows a buffer normally depends on whoever displays it. This
      feature assigns buffers to a configurable set of side windows, and every
      buffer that belongs to one always appears there. It only writes rules
      for Emacs' own `display-buffer-alist` and side windows, plus commands to
      work with them.

      By default there are four side windows. Left and right span the full
      height of the frame; the bottom ones sit between them:

      | Window | Size | Houses |
      |--------|------|--------|
      | `left` | 20% | nothing yet; meant for file and tree lists |
      | `right` | 30% | documentation and help |
      | `bottom-left` | 30% | shells, terminals and REPLs |
      | `bottom-right` | 30% | compilation and grep results |

      - **Matching buffers:** each window lists buffer-name regexps and major
        modes. A mode also matches the modes derived from it, so `comint-mode`
        covers `M-x shell`, `M-x ielm` and other REPLs
      - **Main window:** a buffer opened from a side window that doesn't
        belong there (e.g. a file opened from a shell) goes to the main area,
        so side windows keep their buffers. `C-x b` follows the rules too
      - **Customize:** the layout is the default of
        `tessera-window-management-windows`; changes saved with
        `M-x customize` take precedence

      With the keymaps feature, the commands live under `C-c w`. Each window
      has a key, by default following its position on screen: `h` left, `j`
      bottom-left, `k` bottom-right, `l` right.

      | Keys | Command |
      |------|---------|
      | `C-c w h` | show or hide the left window (likewise `j`, `k`, `l`) |
      | `C-c w w` | show or hide all side windows |
      | `C-c w c h` | cycle the left window's buffers; keep pressing `h` to continue |
      | `C-c w f h` | focus: only the left window, at `focusSize` of the frame |
      | `C-c w F h` | show the left window's buffer as the only window |

      Calling focus or fullscreen again restores the previous layout. Cycling
      goes through the window's buffers in alphabetical order, and showing a
      window picks its most recently used buffer.

      The keys run commands without a prompt, one per window and command,
      e.g. `tessera-window-management-left-toggle`. The general commands
      `tessera-window-management-toggle`, `-toggle-all`, `-cycle`, `-focus`
      and `-fullscreen` read the window name, defaulting to the selected side
      window.

      ```nix
      # another feature claiming its buffers
      features.emacs.window-management.windows.bottom-right.modes = [ "magit-process-mode" ];

      # a host dropping a window and adding one at the top
      features.emacs.window-management.windows = {
        bottom-right.enable = false;
        top = { side = "top"; size = 0.25; names = [ "\\`\\*Messages\\*" ]; };
      };
      ```
    '';
  };

  options = {
    windows = mkOption {
      type = types.attrsOf windowType;
      default = { };
      description = "Side windows; the default of `tessera-window-management-windows`";
    };
    focusSize = mkOption {
      type = types.number;
      default = 0.5;
      description = "Default of `tessera-window-management-focus-size`";
    };
    key = mkOption {
      type = types.str;
      default = "w";
      description = "Key under `C-c` for `tessera-window-management-map`";
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
      cfg = config.features.emacs.window-management;
      windows = lib.filterAttrs (_: w: w.enable) cfg.windows;
      toWindow = name: w: ''
        (${name} :side ${w.side} :slot ${toString w.slot} :size ${toString w.size}${
          lib.optionalString (w.key != null) " :key ${builtins.toJSON w.key}"
        }
         :buffers (${lib.concatStringsSep " " (map builtins.toJSON w.names ++ w.modes)}))'';
    in
    lib.mkMerge [
      {
        features.emacs.window-management.windows = {
          left = {
            key = mkDefault "h";
            side = mkDefault "left";
            size = mkDefault 0.2;
          };
          right = {
            key = mkDefault "l";
            side = mkDefault "right";
            size = mkDefault 0.3;
            names = [ "\\`\\*eldoc" ];
            modes = [
              "help-mode"
              "Info-mode"
              "Man-mode"
              "woman-mode"
              "apropos-mode"
              "shortdoc-mode"
            ];
          };
          bottom-left = {
            key = mkDefault "j";
            side = mkDefault "bottom";
            slot = mkDefault (-1);
            size = mkDefault 0.3;
            modes = [
              "comint-mode"
              "eshell-mode"
              "term-mode"
            ];
          };
          bottom-right = {
            key = mkDefault "k";
            side = mkDefault "bottom";
            slot = mkDefault 1;
            size = mkDefault 0.3;
            modes = [ "compilation-mode" ];
          };
        };
      }

      (mkElispConfig pkgs {
        name = "tessera-window-management";
        summary = "Predictable buffer display in side windows";

        config = ''
          (require 'seq)

          (defgroup tessera-window-management nil
            "Predictable buffer display in side windows."
            :group 'tessera
            :prefix "tessera-window-management-")

          (defcustom tessera-window-management-windows
            '(${lib.concatStringsSep "\n" (lib.mapAttrsToList toWindow windows)})
            "Side windows and the buffers they house.
          Each element is (NAME . PLIST), NAME being a symbol.  PLIST keys:

            :side     `left', `right', `top' or `bottom'.
            :slot     Position among windows on the same side; negative is
                      left/above, positive right/below.
            :size     Width (left/right) or height (top/bottom): a fraction
                      of the frame, or a number of columns/lines.
            :buffers  A string is a regexp matched against buffer names, a
                      symbol a major mode (derived modes match too).
            :key      Key selecting the window in `tessera-window-management-map'."
            :type '(alist :key-type (symbol :tag "Name")
                          :value-type
                          (plist :options
                                 ((:side (choice (const left) (const right)
                                                 (const top) (const bottom)))
                                  (:slot integer)
                                  (:size number)
                                  (:buffers (repeat (choice (regexp :tag "Buffer name")
                                                            (symbol :tag "Major mode"))))
                                  (:key key))))
            :set (lambda (symbol value)
                   (set-default-toplevel-value symbol value)
                   (when (bound-and-true-p tessera-window-management-mode)
                     (tessera-window-management--install))))

          (defcustom tessera-window-management-focus-size ${toString cfg.focusSize}
            "Size of a focused side window, as a fraction of the frame.
          Width for left and right windows, height for top and bottom ones."
            :type 'number)

          (defvar-keymap tessera-window-management-map
            :doc "Keymap of window commands; window keys come from each window's `:key'.")

          (defvar-keymap tessera-window-management-cycle-map
            :doc "Keymap cycling the buffers of the side window behind each key.")

          (defvar-keymap tessera-window-management-focus-map
            :doc "Keymap focusing the side window behind each key.")

          (defvar-keymap tessera-window-management-fullscreen-map
            :doc "Keymap showing the side window behind each key in fullscreen.")

          (defconst tessera-window-management--main-rule
            '(tessera-window-management--same-window-p
              display-buffer-use-some-window
              (some-window . mru)
              (inhibit-same-window . t))
            "Rule showing buffers meant for a side window's own place in the main window.")

          (defvar tessera-window-management--rules nil
            "Entries `tessera-window-management-mode' added to `display-buffer-alist'.")

          (defun tessera-window-management--spec (name)
            "Return the plist of side window NAME."
            (or (alist-get name tessera-window-management-windows)
                (user-error "No side window named `%s'" name)))

          (defun tessera-window-management--condition (spec)
            "Return a `buffer-match-p' condition for the buffers of SPEC."
            `(or ,@(mapcar (lambda (b) (if (stringp b) b `(derived-mode . ,b)))
                           (plist-get spec :buffers))))

          (defun tessera-window-management--alist (spec &optional size)
            "Return the `display-buffer' action alist of SPEC, sized SIZE if non-nil."
            (let ((side (plist-get spec :side)))
              `((side . ,side)
                (slot . ,(or (plist-get spec :slot) 0))
                (,(if (memq side '(left right)) 'window-width 'window-height)
                 . ,(or size (plist-get spec :size)))
                (preserve-size . ,(if (memq side '(left right)) '(t . nil) '(nil . t))))))

          (defun tessera-window-management--window (spec)
            "Return the live side window of SPEC, if any."
            (seq-find (lambda (window)
                        (and (eq (window-parameter window 'window-side) (plist-get spec :side))
                             (eql (window-parameter window 'window-slot)
                                  (or (plist-get spec :slot) 0))))
                      (window-list nil 'nomini)))

          (defun tessera-window-management--buffers (spec)
            "Return the buffers belonging to SPEC, most recently used first."
            (let ((condition (tessera-window-management--condition spec)))
              (seq-filter (lambda (buffer)
                            (and (not (string-prefix-p " " (buffer-name buffer)))
                                 (buffer-match-p condition buffer)))
                          (buffer-list))))

          (defun tessera-window-management--buffer (spec)
            "Return the buffer shown in SPEC's window, else its most recent one."
            (let ((window (tessera-window-management--window spec)))
              (or (and window (window-buffer window))
                  (car (tessera-window-management--buffers spec))
                  (user-error "No buffers for this side window"))))

          (defun tessera-window-management--show (spec buffer &optional size)
            "Display BUFFER in the side window of SPEC and return that window."
            (let ((display-buffer-overriding-action
                   (cons #'display-buffer-in-side-window
                         (tessera-window-management--alist spec size))))
              (display-buffer buffer)))

          (defun tessera-window-management--same-window-p (_buffer &optional action)
            "Non-nil if ACTION wants the selected window and that is a side window."
            (and (window-parameter nil 'window-side)
                 (memq #'display-buffer-same-window (ensure-list (car action)))))

          (defun tessera-window-management--delete-side-windows ()
            "Delete all side windows of the selected frame."
            (dolist (window (window-list nil 'nomini))
              (when (window-parameter window 'window-side)
                (delete-window window))))

          (defun tessera-window-management--save (command name)
            "Remember the layout before COMMAND changed it for window NAME."
            (set-frame-parameter nil 'tessera-window-management--state
                                 (list command name (current-window-configuration))))

          (defun tessera-window-management--restore (command name)
            "Restore the layout saved by `tessera-window-management--save'.
          Return non-nil if COMMAND for window NAME saved it."
            (pcase (frame-parameter nil 'tessera-window-management--state)
              (`(,saved-command ,saved-name ,configuration)
               (set-frame-parameter nil 'tessera-window-management--state nil)
               (set-window-configuration configuration)
               (and (eq saved-command command) (eq saved-name name)))))

          (defun tessera-window-management--name (window)
            "Return the name of the side window WINDOW is, if any."
            (car (seq-find (lambda (entry)
                             (eq (tessera-window-management--window (cdr entry)) window))
                           tessera-window-management-windows)))

          (defun tessera-window-management--read ()
            "Read a side window name, defaulting to the selected one."
            (let ((default (tessera-window-management--name (selected-window))))
              (intern (completing-read
                       (format-prompt "Side window" default)
                       (mapcar (lambda (entry) (symbol-name (car entry)))
                               tessera-window-management-windows)
                       nil t nil nil (and default (symbol-name default))))))

          (defun tessera-window-management-cycle (name)
            "Show the next buffer of side window NAME, showing the window if hidden."
            (interactive (list (tessera-window-management--read)))
            (let* ((spec (tessera-window-management--spec name))
                   (window (tessera-window-management--window spec))
                   (buffers (sort (tessera-window-management--buffers spec)
                                  (lambda (a b) (string< (buffer-name a) (buffer-name b))))))
              (unless buffers
                (user-error "No buffers for side window `%s'" name))
              (tessera-window-management--show
               spec (if window
                        (or (cadr (memq (window-buffer window) buffers)) (car buffers))
                      (tessera-window-management--buffer spec)))))

          (defun tessera-window-management-toggle (name)
            "Show or hide side window NAME."
            (interactive (list (tessera-window-management--read)))
            (let* ((spec (tessera-window-management--spec name))
                   (window (tessera-window-management--window spec)))
              (if window
                  (delete-window window)
                (tessera-window-management--show spec (tessera-window-management--buffer spec)))))

          (defun tessera-window-management-toggle-all ()
            "Hide all side windows if any is shown, otherwise show all of them.
          Windows without buffers stay hidden."
            (interactive)
            (let ((specs (mapcar #'cdr tessera-window-management-windows)))
              (if-let* ((windows (delq nil (mapcar #'tessera-window-management--window specs))))
                  (mapc #'delete-window windows)
                (or (seq-filter #'identity
                                (mapcar (lambda (spec)
                                          (when-let* ((buffer (car (tessera-window-management--buffers spec))))
                                            (tessera-window-management--show spec buffer)))
                                        specs))
                    (user-error "No side window has buffers to show")))))

          (defun tessera-window-management-focus (name)
            "Show only side window NAME, sized `tessera-window-management-focus-size'.
          Call again to restore the previous layout."
            (interactive (list (tessera-window-management--read)))
            (unless (tessera-window-management--restore 'focus name)
              (let* ((spec (tessera-window-management--spec name))
                     (buffer (tessera-window-management--buffer spec)))
                (tessera-window-management--save 'focus name)
                (tessera-window-management--delete-side-windows)
                (select-window (tessera-window-management--show
                                spec buffer tessera-window-management-focus-size)))))

          (defun tessera-window-management-fullscreen (name)
            "Show the buffer of side window NAME as the only window.
          Call again to restore the previous layout."
            (interactive (list (tessera-window-management--read)))
            (unless (tessera-window-management--restore 'fullscreen name)
              (let ((buffer (tessera-window-management--buffer
                             (tessera-window-management--spec name))))
                (tessera-window-management--save 'fullscreen name)
                (tessera-window-management--delete-side-windows)
                (delete-other-windows)
                (set-window-dedicated-p nil nil)
                (set-window-buffer nil buffer))))

          (defun tessera-window-management--define-commands ()
            "Define `tessera-window-management-NAME-COMMAND' for every side window."
            (dolist (entry tessera-window-management-windows)
              (dolist (command '(cycle toggle focus fullscreen))
                (let ((name (car entry))
                      (fn (intern (format "tessera-window-management-%s" command))))
                  (defalias (intern (format "tessera-window-management-%s-%s" name command))
                    (lambda () (interactive) (funcall fn name))
                    (format "Call `%s' on side window `%s'." fn name))))))

          (defun tessera-window-management--define-keys ()
            "Rebuild `tessera-window-management-map' from the windows' `:key'."
            (let ((maps `((toggle . ,tessera-window-management-map)
                          (cycle . ,tessera-window-management-cycle-map)
                          (focus . ,tessera-window-management-focus-map)
                          (fullscreen . ,tessera-window-management-fullscreen-map))))
              (dolist (map maps) (setcdr (cdr map) nil))
              (keymap-set tessera-window-management-map "w" '("all side windows" . tessera-window-management-toggle-all))
              (keymap-set tessera-window-management-map "c" (cons "cycle" tessera-window-management-cycle-map))
              (keymap-set tessera-window-management-map "f" (cons "focus" tessera-window-management-focus-map))
              (keymap-set tessera-window-management-map "F" (cons "fullscreen" tessera-window-management-fullscreen-map))
              (dolist (entry tessera-window-management-windows)
                (when-let* ((key (plist-get (cdr entry) :key))
                            (name (symbol-name (car entry))))
                  (pcase-dolist (`(,command . ,map) maps)
                    (keymap-set map key
                                (cons name
                                      (intern (format "tessera-window-management-%s-%s"
                                                      (car entry) command)))))
                  (put (intern (format "tessera-window-management-%s-cycle" (car entry)))
                       'repeat-map 'tessera-window-management-cycle-map)))))

          (defun tessera-window-management--uninstall ()
            "Remove the rules added by `tessera-window-management--install'."
            (setq display-buffer-alist
                  (seq-difference display-buffer-alist tessera-window-management--rules #'eq)
                  tessera-window-management--rules nil))

          (defun tessera-window-management--install ()
            "Add the side window rules to `display-buffer-alist'."
            (tessera-window-management--uninstall)
            (setq tessera-window-management--rules
                  (append (mapcar (lambda (entry)
                                    (cons (tessera-window-management--condition (cdr entry))
                                          (cons #'display-buffer-in-side-window
                                                (tessera-window-management--alist (cdr entry)))))
                                  tessera-window-management-windows)
                          (list tessera-window-management--main-rule))
                  display-buffer-alist
                  (append tessera-window-management--rules display-buffer-alist))
            (tessera-window-management--define-commands)
            (tessera-window-management--define-keys))

          ;;;###autoload
          (define-minor-mode tessera-window-management-mode
            "Display buffers in the side windows of `tessera-window-management-windows'."
            :global t
            (if tessera-window-management-mode
                (tessera-window-management--install)
              (tessera-window-management--uninstall)))
        '';
      })

      {
        programs.emacs.extraConfig = ''
          (setopt window-sides-vertical t
                  switch-to-buffer-obey-display-actions t)
          (tessera-window-management-mode 1)
          (with-eval-after-load 'tessera-keymaps
            (keymap-set mode-specific-map "${cfg.key}" (cons "windows" tessera-window-management-map)))
        '';
      }
    ];
}
