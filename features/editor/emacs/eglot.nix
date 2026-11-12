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
        their language servers and start Eglot in their buffers when this
        feature is enabled; `M-x eglot` starts it elsewhere
      - Several language servers in a buffer, e.g. typescript-language-server
        and ESLint's, run as one through rassumfrassum. Formatting goes to the
        first of the others that can format, else to the first
      - A server shuts down with its last buffer, edits the
        server proposes are applied without confirmation, files reached
        through go to definition (e.g. libraries) are managed too
      - The echo area shows an eldoc hint and a quick action hint.
        Pressing `M-n` shows the hints if they are hidden and cycles
        between them if there are multiple
      - Flymake runs only in trusted files under Emacs 31, so diagnostics need
        their directories in `trusted-content`, e.g.
        `(setopt trusted-content '("~/src/"))`
      - Language features configure their servers through
        `eglot-workspace-configuration`. A project that sets it in its
        `.dir-locals.el` replaces their settings there

      Eglot works through Emacs' own facilities, so their keys keep working.
      With the keymaps feature, Eglot's own commands live directly under
      `C-c c`, only in buffers Eglot manages. They work the same in every
      language; `C-c c u` holds a language's own utilities. Refactorings
      the language server offers, such as extracting a function or inlining
      a variable, are code actions.

      `C-c c s` holds the source actions: code actions for the whole buffer,
      which servers only offer when asked for by kind. Which ones there are
      depends on the server: typescript-language-server has them all,
      ESLint and Biome fix all. If several servers offer one, you choose.

      | Keys | Command |
      |------|---------|
      | `M-.`, `M-?` | go to definition, find references |
      | `C-M-.` | find a symbol in the project |
      | `C-h .` | documentation at point |
      | `M-n` | next documentation in the echo area |
      | `M-g f` | diagnostics (with the completion feature) |
      | `C-c c a` | code actions at point |
      | `C-c c f` | format the region or buffer |
      | `C-c c i`, `C-c c t` | go to implementation, type definition |
      | `C-c c q` | quick fix |
      | `C-c c r` | rename |
      | `C-c c s o` | organize imports |
      | `C-c c s f` | fix all |
      | `C-c c s u` | remove unused code |
      | `C-c c s i`, `C-c c s r` | add missing imports, remove unused ones |
      | `C-c c s s` | sort imports |
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
      rassPreset = pkgs.writeText "tessera.py" ''
        """Tessera's preset for rassumfrassum.

        The servers come from the command line: the primary one first, then
        the others in the order they format. Language features extend Logic
        in their own presets.
        """

        from rassumfrassum.frassum import DirectResponse, LspLogic

        CAPABILITIES = {
            "textDocument/formatting": "documentFormattingProvider",
            "textDocument/rangeFormatting": "documentRangeFormattingProvider",
            "textDocument/codeAction": "codeActionProvider",
        }


        class Logic(LspLogic):
            async def on_server_request(self, method, params, source):
                # Servers like Biome and ESLint register capabilities after
                # starting. Record those rass routes by, which it only takes from
                # initialize, and answer all but the file watchers Eglot supports
                if method in ("client/registerCapability", "client/unregisterCapability"):
                    key = "registrations" if method.startswith("client/register") else "unregisterations"
                    rest = []
                    for registration in params.get(key, []):
                        if registration.get("method") == "workspace/didChangeWatchedFiles":
                            rest.append(registration)
                        elif capability := CAPABILITIES.get(registration.get("method")):
                            if key == "registrations":
                                source.caps[capability] = registration.get("registerOptions") or True
                            else:
                                source.caps.pop(capability, None)
                    if not rest:
                        return DirectResponse(payload=None)
                    params[key] = rest
                return await super().on_server_request(method, params, source)

            async def on_client_request(self, method, params, servers):
                # The first secondary server that formats, else the primary one
                if capability := {
                    "textDocument/formatting": "documentFormattingProvider",
                    "textDocument/rangeFormatting": "documentRangeFormattingProvider",
                }.get(method):
                    return [s for s in servers[1:] + servers[:1] if s.caps.get(capability)][:1]
                return await super().on_client_request(method, params, servers)


        def logic_class():
            return Logic
      '';
      rass = pkgs.rassumfrassum.overridePythonAttrs (old: {
        postInstall = (old.postInstall or "") + ''
          cp ${rassPreset} $out/${pkgs.python3Packages.python.sitePackages}/rassumfrassum/presets/tessera.py
        '';
      });
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

          (defvar tessera-eglot-workspace-configuration-functions nil
            "Functions returning sections of the workspace configuration.
          Each is called with the server and returns a plist of sections, see
          `eglot-workspace-configuration'.  They run with the project's
          directory-local variables, so a project can change the variables they
          read.  Language features add to it.")

          (defun tessera-eglot-workspace-configuration (server)
            "Return the sections of `tessera-eglot-workspace-configuration-functions'.
          SERVER is passed on to them."
            (seq-mapcat (lambda (function) (funcall function server))
                        tessera-eglot-workspace-configuration-functions))

          (with-eval-after-load 'eglot
            (keymap-set eglot-mode-map "M-n" #'tessera-eglot-next-doc)
            (setq-default eglot-workspace-configuration #'tessera-eglot-workspace-configuration))

          (defun tessera-eglot-contact (servers &optional preset)
            "Return an Eglot contact for SERVERS, a list of language server commands.
          That is the only one of them, or rassumfrassum running them as one,
          the first as the primary server.  Formatting goes to the first of the
          others that can format, else to the primary one.  PRESET is the file
          of a rassumfrassum preset extending `rassumfrassum.presets.tessera',
          e.g. with a language's own settings."
            (if (cdr servers)
                `("${rass}/bin/rass" "--log-level" "warn" ,(or preset "tessera")
                  ,@(seq-mapcat (lambda (server) (cons "--" server)) servers))
              (car servers)))

          (defun tessera-eglot--merge-document-changes (changes)
            "Return CHANGES with the text edits of each document in one entry.
          Eglot checks each entry against the buffer's version, so a second entry
          for a document the first one changed would fail; servers like
          typescript-language-server send several for fix all."
            (let (merged)
              (seq-doseq (change changes)
                (if-let* (((not (plist-get change :kind)))
                          (previous (seq-find (lambda (other)
                                                (and (not (plist-get other :kind))
                                                     (equal (plist-get other :textDocument)
                                                            (plist-get change :textDocument))))
                                              merged)))
                    (plist-put previous :edits (vconcat (plist-get previous :edits)
                                                        (plist-get change :edits)))
                  (push change merged)))
              (vconcat (nreverse merged))))

          (with-eval-after-load 'eglot
            (cl-defmethod eglot-execute :before (_server action)
              "Merge the edits ACTION makes to the same document."
              (when-let* ((edit (plist-get action :edit))
                          (changes (plist-get edit :documentChanges)))
                (plist-put edit :documentChanges (tessera-eglot--merge-document-changes changes)))))

          (defmacro tessera-eglot--define-source-action (name kind doc)
            "Define NAME, a command executing the KIND code actions of the buffer.
          DOC begins its docstring."
            `(defun ,name ()
               ,(format "%s\nThat is the code action of kind %S for the whole buffer;\nif several servers offer one, choose." doc kind)
               (interactive)
               (eglot-code-actions (point-min) (point-max) ,kind t)))

          (tessera-eglot--define-source-action tessera-eglot-organize-imports
            "source.organizeImports" "Organize the imports.")
          (tessera-eglot--define-source-action tessera-eglot-fix-all
            "source.fixAll" "Fix all problems that can be fixed.")
          (tessera-eglot--define-source-action tessera-eglot-remove-unused
            "source.removeUnused" "Remove unused code.")
          (tessera-eglot--define-source-action tessera-eglot-add-missing-imports
            "source.addMissingImports" "Add the missing imports.")
          (tessera-eglot--define-source-action tessera-eglot-remove-unused-imports
            "source.removeUnusedImports" "Remove the unused imports.")
          (tessera-eglot--define-source-action tessera-eglot-sort-imports
            "source.sortImports" "Sort the imports.")

          (defvar-keymap tessera-eglot-source-map
            :doc "Keymap of the code actions for the whole buffer."
            "f" '("fix all" . tessera-eglot-fix-all)
            "i" '("add missing imports" . tessera-eglot-add-missing-imports)
            "o" '("organize imports" . tessera-eglot-organize-imports)
            "r" '("remove unused imports" . tessera-eglot-remove-unused-imports)
            "s" '("sort imports" . tessera-eglot-sort-imports)
            "u" '("remove unused code" . tessera-eglot-remove-unused))

          (defvar-keymap tessera-eglot-map
            :doc "Keymap of Eglot commands for the buffers it manages."
            "a" '("code actions (point)" . eglot-code-actions)
            "f" '("format" . eglot-format)
            "i" '("go to implementation" . eglot-find-implementation)
            "q" '("quick fix" . eglot-code-action-quickfix)
            "r" '("rename" . eglot-rename)
            "s" (cons "code actions (buffer)" tessera-eglot-source-map)
            "t" '("go to type definition" . eglot-find-typeDefinition))
        '';
      })

      {
        programs.emacs.extraConfig = ''
          (with-eval-after-load 'tessera-keymaps
            (with-eval-after-load 'eglot
              (keymap-set eglot-mode-map "C-c ${keys.code}" (cons "code" tessera-eglot-map))))
        '';
      }
    ];
}
