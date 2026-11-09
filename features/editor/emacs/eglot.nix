{
  mkFeature,
  mkElispConfig,
  ...
}:

mkFeature {
  name = [
    "emacs"
    "eglot"
  ];

  doc = {
    summary = "Language servers in Emacs through Eglot";
    description = ''
      Configures Eglot, Emacs' built-in lsp client, which
      displays completion, diagnostics, documentation, navigation and
      refactoring from a language server in the buffer.

      - Language features (e.g. the javascript feature) bring
        their language server and start Eglot in their buffers when this
        feature is enabled; `M-x eglot` starts it elsewhere
      - A server shuts down with its last buffer, edits the
        server proposes are applied without confirmation, files reached
        through go to definition (e.g. libraries) are managed too
      - The echo area shows an eldoc hint and a quick action hint.
        Pressing `M-n` shows the hints if they are hidden and cycles
        between them if there are multiple
      - Formatting uses the formatter that matched in `tessera-eglot-formatters`
        or `eglot-format` as a fallback. Language features may add formatters
        to `tessera-eglot-formatters`

      Eglot works through Emacs' own facilities, so their keys keep working.
      With the keymaps feature, Eglot's own commands live directly under
      `C-c c`, only in buffers Eglot manages. They work the same in every
      language; `C-c c u` holds a language's own utilities. Refactorings
      the language server offers, such as extracting a function or inlining
      a variable, are code actions.

      | Keys | Command |
      |------|---------|
      | `M-.`, `M-?` | go to definition, find references |
      | `C-M-.` | find a symbol in the project |
      | `C-h .` | documentation at point |
      | `M-n` | next documentation in the echo area |
      | `M-g f` | diagnostics (with the completion feature) |
      | `C-c c a` | code actions |
      | `C-c c f` | format the file with the project's formatter or `eglot-format` |
      | `C-c c i`, `C-c c t` | go to implementation, type definition |
      | `C-c c o` | organize imports |
      | `C-c c q` | quick fix |
      | `C-c c r` | rename |
    '';
  };

  home =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (config.features.emacs.keymaps) keys;
    in
    lib.mkMerge [
      (mkElispConfig pkgs {
        name = "tessera-eglot";
        summary = "Language servers through Eglot";

        elispPackages =
          epkgs: with epkgs; [
            markdown-mode
          ];

        config = ''
          (setopt eglot-autoshutdown t
                  eglot-extend-to-xref t
                  eglot-confirm-server-edits nil
                  eldoc-echo-area-use-multiline-p t)

          (defvar-local tessera-eglot--docs nil
            "Documentation at point from the last ElDoc request, the one shown first.")

          (defvar-local tessera-eglot--action nil
            "Eglot's code action hint from the last ElDoc request.")

          (defun tessera-eglot--echo-line (doc)
            "Return the first line of DOC, an ElDoc item, cut to fit the echo area."
            (pcase-let* ((`(,string . ,plist) doc)
                         (echo (plist-get plist :echo))
                         (thing (plist-get plist :thing)))
              (with-temp-buffer
                (insert (cond ((integerp echo) (substring string 0 echo))
                              ((stringp echo) echo)
                              (t string)))
                ;; Drop markup hidden by rendering, e.g. the code fences of hover
                (let ((pos (point-min)))
                  (while (< pos (point-max))
                    (let ((next (next-single-char-property-change pos 'invisible)))
                      (if (invisible-p pos) (delete-region pos next) (setq pos next)))))
                (truncate-string-to-width
                 (concat (and thing (concat (propertize (format "%s" thing)
                                                        'face (plist-get plist :face))
                                            ": "))
                         (car (split-string (string-trim (buffer-string)) "\n")))
                 (1- (window-width (minibuffer-window)))
                 nil nil t))))

          (defun tessera-eglot--show-docs (interactive)
            "Show the first of `tessera-eglot--docs' and `tessera-eglot--action'.
          INTERACTIVE is passed on to `eldoc-display-in-echo-area'."
            (let ((eldoc-echo-area-use-multiline-p 2)
                  ;; Shrink the echo area too, when there's no code action hint
                  (resize-mini-windows t))
              (eldoc-display-in-echo-area
               (mapcar (lambda (doc) (list (tessera-eglot--echo-line doc)))
                       (delq nil (list (car tessera-eglot--docs) tessera-eglot--action)))
               interactive)))

          (defun tessera-eglot--display-docs (docs interactive)
            "Show one of DOCS and Eglot's code action hint in the echo area, a line each.
          A replacement for `eldoc-display-in-echo-area' in the buffers Eglot
          manages; `tessera-eglot-next-doc' shows the next of DOCS."
            (let ((action-p (lambda (doc)
                              (eq (plist-get (cdr doc) :origin)
                                  #'eglot-code-action-suggestion))))
              (setq tessera-eglot--docs (seq-remove action-p docs)
                    tessera-eglot--action (seq-find action-p docs)))
            (tessera-eglot--show-docs interactive))

          (defun tessera-eglot-next-doc ()
            "Show the next documentation at point in the echo area."
            (interactive)
            (unless (cdr tessera-eglot--docs)
              (user-error "No other documentation at point"))
            (setq tessera-eglot--docs (append (cdr tessera-eglot--docs)
                                              (list (car tessera-eglot--docs))))
            (tessera-eglot--show-docs t))

          (defun tessera-eglot--setup-eldoc ()
            "Display ElDoc's documentation with `tessera-eglot--display-docs'."
            (if (eglot-managed-p)
                (setq-local eldoc-display-functions
                            (cl-substitute #'tessera-eglot--display-docs
                                           #'eldoc-display-in-echo-area
                                           eldoc-display-functions))
              (kill-local-variable 'eldoc-display-functions)))

          (add-hook 'eglot-managed-mode-hook #'tessera-eglot--setup-eldoc)

          (with-eval-after-load 'eglot
            (keymap-set eglot-mode-map "M-n" #'tessera-eglot-next-doc))

          (defvar tessera-eglot-formatters nil
            "Formatters of projects, which `tessera-eglot-format' prefers to Eglot.
          Each element is (MODES FILES COMMAND), added by language features.  It
          applies in buffers whose major mode derives from one of MODES, when one
          of FILES, e.g. the formatter's configuration, is in the buffer's
          directory or above.  COMMAND is a list of a program and its arguments,
          which formats the file given after them in place, or a function
          returning one, called in the buffer.")

          (defun tessera-eglot-formatter ()
            "Return the command formatting the file of the current buffer, or nil.
          It is the command of the first of `tessera-eglot-formatters' that
          applies, followed by the file."
            (when buffer-file-name
              (seq-some (pcase-lambda (`(,modes ,files ,command))
                          (and (derived-mode-p modes)
                               (seq-some (lambda (file) (locate-dominating-file default-directory file))
                                         files)
                               (append (if (functionp command) (funcall command) command)
                                       (list (file-local-name buffer-file-name)))))
                        tessera-eglot-formatters)))

          (defun tessera-eglot-format ()
            "Format with the project's formatter, or with Eglot if there is none.
          The project's formatter, see `tessera-eglot-formatter', formats the
          whole file after saving the buffer, and shows its output when it
          fails.  `eglot-format' formats the region or the buffer."
            (interactive)
            (if-let* ((command (tessera-eglot-formatter)))
                (let ((output (get-buffer-create "*Format*")))
                  (save-buffer)
                  (with-current-buffer output
                    (erase-buffer))
                  (let ((status (apply #'process-file (car command) nil output nil (cdr command))))
                    (unless (verify-visited-file-modtime)
                      (revert-buffer-with-fine-grain t t))
                    (unless (eql status 0)
                      (with-current-buffer output
                        (ansi-color-apply-on-region (point-min) (point-max)))
                      (display-buffer output)
                      (message "Formatter exited with %s" status))))
              (call-interactively #'eglot-format)))

          (defvar-keymap tessera-eglot-map
            :doc "Keymap of Eglot commands for the buffers it manages."
            "a" #'eglot-code-actions
            "f" #'tessera-eglot-format
            "i" #'eglot-find-implementation
            "o" #'eglot-code-action-organize-imports
            "q" #'eglot-code-action-quickfix
            "r" #'eglot-rename
            "t" #'eglot-find-typeDefinition)
        '';
      })

      {
        programs.emacs.extraConfig = ''
          (with-eval-after-load 'tessera-keymaps
            (with-eval-after-load 'eglot
              (keymap-set eglot-mode-map "C-c ${keys.code}" (cons "Code" tessera-eglot-map))))
        '';
      }
    ];
}
