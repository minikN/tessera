{
  lib,
  mkFeature,
  mkElispConfig,
  ...
}:

mkFeature {
  name = "json";

  doc = {
    summary = "JSON and JSON5 development environment";
    description = ''
      Sets the editor up for JSON, JSONC and JSON5.

      | | JSON | JSONC | JSON5 |
      |---|---|---|---|
      | Files | `.json` | `.jsonc`, `tsconfig.json`, `jsconfig.json`, `devcontainer.json`, `deno.json`, `.vscode/*.json`, … | `.json5` |
      | Language server | vscode-json-language-server | vscode-json-language-server | - |
      | Formatting | the project's Biome or oxfmt, else vscode-json-language-server | the project's Biome or oxfmt, else vscode-json-language-server | oxfmt |
      | Linting | vscode-json-language-server (syntax, duplicate keys, schemas), the project's Biome | vscode-json-language-server (syntax, duplicate keys, schemas), the project's Biome | - |

      - two spaces
      - vscode-json-language-server comes from `packages.jsonls.package`.
      - a file is validated against the schema in its `$schema` key, or
        the one `schemas` sets for its name
      - JSON5 has no language server of its own; oxfmt's formats it

      ```nix
      features.json = {
        enable = true;
        utils.enable = true;
        schemas = {
          "renovate.json" = "https://docs.renovatebot.com/renovate-schema.json";
          "*.foo.json" = ./foo.schema.json;
        };
      };
      ```

      ## With Emacs

      - the grammars come with this feature, so Emacs never asks to install
        them
      - Eglot starts the language server when the emacs.eglot feature is
        enabled; in JSON5 files that is oxfmt's
      - it supports the following formatters: `biome` and `oxfmt`. If the
        project sets one up, found by its configuration file in the file's
        directory or above, its language server runs next to
        vscode-json-language-server through rassumfrassum. Biome lints too
      - `eglot-format` will use the formatter's LSP to format the document if
        one is defined. If not, it's routed through vscode-json-language-server
        as a fallback
      - the code action "Sort JSON" (`C-c c a`), offered by vscode-json-language-server,
        sorts the keys of every object in the document; json-utils' `C-c c u s`
        only those of the object at point
      - formatters are the project's own (`node_modules/.bin`) if it has
        them, otherwise the ones from nixpkgs
      - if `features.emacs.package` is built without tree-sitter, JSON files
        open in `js-json-mode`, JSON5 files get no mode and home-manager prints
        a warning
      - `schemas` is the default of `tessera-json-schemas`, which
        `M-x customize-group tessera-json` changes. A project's
        `.dir-locals.el` can set its own; files are relative to the project
        root, and `M-x eglot-reconnect` applies a change:

      ```elisp
      ((nil . ((tessera-json-schemas
                . (("*.foo.json" . "schemas/foo.schema.json")
                   ("renovate.json" . "https://docs.renovatebot.com/renovate-schema.json"))))))
      ```

      ## Utility package

      `utils.enable` adds tessera's json-utils package. With the keymaps
      feature, `C-c c u` holds its commands in JSON and JSON5 buffers (with
      tree-sitter). Commands the javascript feature has too are under the
      same keys there:

      | Keys | Command |
      |------|---------|
      | `C-c c u x`, `C-c c u c` | one element per line, or all on one line |
      | `C-c c u k` | kill to the end of the line, the object, the array or the string |
      | `C-c c u j` | copy the jq path of the value at point, e.g. `.a[2].b` |
      | `C-c c u s` | sort the keys of the object at point (in JavaScript, `s` splits strings) |
    '';
  };

  options =
    { pkgs, ... }:
    {
      packages = {
        jsonls.package = lib.mkPackageOption pkgs "vscode-langservers-extracted" {
          extraDescription = "Provides the JSON language server.";
        };
        nodejs.package = lib.mkPackageOption pkgs "nodejs" {
          extraDescription = "Provides Node.js for the project's own Biome and oxfmt.";
        };
      };

      schemas = lib.mkOption {
        type = with lib.types; attrsOf (coercedTo path (path: "${path}") str);
        default = { };
        example = lib.literalExpression ''
          {
            "renovate.json" = "https://docs.renovatebot.com/renovate-schema.json";
            "*.foo.json" = ./foo.schema.json;
          }
        '';
        description = "JSON schemas by file name pattern, as a file or a URL. The default of `tessera-json-schemas` in Emacs.";
      };

      utils.enable = lib.mkEnableOption "json-utils, editing commands for JSON and JSON5 in Emacs";
    };

  home =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.features.json;
      inherit (config.features) emacs;
      inherit (emacs.keymaps) keys;
      treesit = emacs.package.withTreeSitter or false;
      oxfmt = "${pkgs.oxfmt}/bin/oxfmt";
      jsoncFiles = [
        "*.jsonc"
        "tsconfig.json"
        "tsconfig.*.json"
        "jsconfig.json"
        "jsconfig.*.json"
        ".eslintrc.json"
        ".babelrc.json"
        "babel.config.json"
        "devcontainer.json"
        ".devcontainer.json"
        ".vscode/*.json"
        "deno.json"
      ];
      schemas = lib.concatStringsSep " " (
        lib.mapAttrsToList (
          pattern: schema: "(${builtins.toJSON pattern} . ${builtins.toJSON schema})"
        ) cfg.schemas
      );
    in
    lib.mkIf emacs.enable (
      lib.mkMerge [
        {
          warnings =
            lib.optional (!treesit)
              "features.json: features.emacs.package is built without tree-sitter; JSON files use js-json-mode and JSON5 isn't supported.";
        }

        (mkElispConfig pkgs {
          name = "tessera-json";
          summary = "JSON and JSON5";
          elispPackages =
            epkgs:
            lib.optionals treesit (
              [
                epkgs.json5-ts-mode
                (epkgs.treesit-grammars.with-grammars (
                  g: with g; [
                    tree-sitter-json
                    tree-sitter-json5
                  ]
                ))
              ]
              ++ lib.optional cfg.utils.enable (pkgs.tessera.json-utils.override { emacsPackages = epkgs; })
            );

          config = ''
            (add-to-list 'auto-mode-alist '("\\.jsonc\\'" . js-json-mode))
            ${lib.optionalString treesit ''
              (add-to-list 'auto-mode-alist '("\\.json5\\'" . json5-ts-mode))
              (setopt treesit-enabled-modes
                      (if (eq treesit-enabled-modes t)
                          t
                        (seq-union treesit-enabled-modes '(json-ts-mode))))
            ''}
            ${lib.optionalString config.features.emacs.eglot.enable ''

              (defgroup tessera-json nil
                "JSON, JSONC and JSON5."
                :group 'tessera)

              (defcustom tessera-json-schemas '(${schemas})
                "JSON schemas by file name pattern.
              An alist of (PATTERN . SCHEMA), e.g. (\"*.foo.json\" . \"foo.schema.json\").
              SCHEMA is a URL or a file, relative to the project's root.  Set it in a
              project's .dir-locals.el to use other schemas there; the language
              server reads it when it starts."
                :type '(alist :key-type (string :tag "File name pattern")
                              :value-type (string :tag "Schema file or URL"))
                :safe (lambda (value)
                        (and (listp value)
                             (seq-every-p (lambda (entry)
                                            (and (consp entry) (stringp (car entry)) (stringp (cdr entry))))
                                          value)))
                :group 'tessera-json)

              (defconst tessera-json--jsonc-files
                [${lib.concatMapStringsSep " " builtins.toJSON jsoncFiles}]
                "Files that may have comments and trailing commas.")

              (defun tessera-json--workspace-configuration (_server)
                "Return the settings of vscode-json-language-server.
              Its schemas come from `tessera-json-schemas'."
                `(:json
                  (:validate (:enable t)
                   :schemas
                   ,(vconcat
                     `((:fileMatch ,tessera-json--jsonc-files
                        :schema (:allowComments t :allowTrailingCommas t)))
                     (mapcar (pcase-lambda (`(,pattern . ,schema))
                               `(:fileMatch [,pattern]
                                 :url ,(if (string-match-p "\\`[[:alpha:]][[:alnum:]+.-]+:" schema)
                                           schema
                                         (eglot-path-to-uri (expand-file-name schema)))))
                             tessera-json-schemas)))))

              (defun tessera-json--project-command (command)
                "Return COMMAND, with the project's own program if it has one.
              That is the program of the same name in node_modules/.bin, run with
              Node.js first in `PATH'."
                (let ((bin (concat "node_modules/.bin/" (file-name-nondirectory (car command)))))
                  (if-let* ((dir (locate-dominating-file default-directory bin)))
                      `("${pkgs.coreutils}/bin/env"
                        ,(concat "PATH=${cfg.packages.nodejs.package}/bin:" (getenv "PATH"))
                        ,(file-local-name (expand-file-name bin dir))
                        ,@(cdr command))
                    command)))

              (defconst tessera-json--tool-servers
                '((("biome.json" "biome.jsonc" ".biome.json" ".biome.jsonc")
                   "${pkgs.biome}/bin/biome" "lsp-proxy")
                  ((".oxfmtrc.json" ".oxfmtrc.jsonc" "oxfmt.config.ts")
                   "${oxfmt}" "--lsp"))
                "Language servers of the tools, after their configuration files.
              In the order they format.")

              (defun tessera-json--language-server (&rest _)
                "Return the language servers for the current JSON buffer.
              vscode-json-language-server, with the servers of the tools the project
              sets up, see `tessera-eglot-contact'."
                (cons 'tessera-json--jsonls
                      (append
                       (tessera-eglot-contact
                        (cons '("${cfg.packages.jsonls.package}/bin/vscode-json-language-server" "--stdio")
                              (seq-keep (pcase-lambda (`(,files . ,command))
                                          (and (seq-some (lambda (file) (locate-dominating-file default-directory file))
                                                         files)
                                               (tessera-json--project-command command)))
                                        tessera-json--tool-servers)))
                       ;; vscode-json-language-server only formats when told to
                       '(:initializationOptions (:provideFormatter t)))))

              (defun tessera-json--json5-server (&rest _)
                "Return oxfmt's language server, the project's own if it has one."
                (cons 'tessera-json--oxfmt
                      (tessera-json--project-command '("${oxfmt}" "--lsp"))))

              (with-eval-after-load 'eglot
                (defclass tessera-json--jsonls (eglot-lsp-server) ()
                  :documentation "vscode-json-language-server, maybe through rassumfrassum.")

                (cl-defmethod eglot-execute ((server tessera-json--jsonls) action)
                  "Execute ACTION, sorting the document for the command \"json.sort\".
              The server leaves that one to the client, which asks it for the edits."
                  (if (equal (plist-get action :command) "json.sort")
                      (eglot--apply-text-edits
                       (jsonrpc-request server :json/sort
                                        `(,@(eglot--TextDocumentIdentifier)
                                          :options (:tabSize ,tab-width
                                                    :insertSpaces ,(if indent-tabs-mode :json-false t)))))
                    (cl-call-next-method)))

                (defclass tessera-json--oxfmt (eglot-lsp-server) ()
                  :documentation "oxfmt's language server in JSON5 buffers.")

                (cl-defmethod eglot-client-capabilities ((_ tessera-json--oxfmt))
                  "Keep oxfmt from asking to watch its configuration files.
              Eglot would watch every directory of the project, which runs out of
              file descriptors in large ones."
                  (let ((capabilities (cl-call-next-method)))
                    (plist-put (plist-get capabilities :workspace)
                               :didChangeWatchedFiles '(:dynamicRegistration :json-false))
                    capabilities))

                (add-to-list 'eglot-server-programs
                             '(((json-ts-mode :language-id "json")
                                (js-json-mode :language-id "json"))
                               . tessera-json--language-server))
                (add-to-list 'eglot-server-programs
                             '((json5-ts-mode :language-id "json5") . tessera-json--json5-server))
                (add-hook 'tessera-eglot-workspace-configuration-functions
                          #'tessera-json--workspace-configuration))

              (defun tessera-json--eglot-ensure ()
                "Start Eglot, formatting with the mode's indentation."
                (require 'eglot)
                ;; tree-sitter does this way better than the lsp
                (setq-local eglot-stay-out-of (cons 'imenu eglot-stay-out-of))
                ;; Eglot passes `tab-width' as the indentation to format with
                (setq-local tab-width (pcase major-mode
                                        ('json5-ts-mode json5-ts-mode-indent-offset)
                                        ('json-ts-mode json-ts-indent-offset)
                                        (_ js-indent-level)))
                (eglot-ensure))
              (add-hook 'json-ts-mode-hook #'tessera-json--eglot-ensure)
              (add-hook 'json5-ts-mode-hook #'tessera-json--eglot-ensure)
              (add-hook 'js-json-mode-hook #'tessera-json--eglot-ensure)
            ''}
          '';
        })

        (lib.mkIf (cfg.utils.enable && treesit) {
          programs.emacs.extraConfig = ''
            (with-eval-after-load 'tessera-keymaps
              (require 'tessera-json-utils)
              (defvar-keymap tessera-json-code-map
                :doc "Keymap under `C-c c' in JSON and JSON5 buffers."
                "u" (cons "utils" tessera-json-utils-map))
              (with-eval-after-load 'json-ts-mode
                (keymap-set json-ts-mode-map "C-c ${keys.code}" (cons "code" tessera-json-code-map)))
              (with-eval-after-load 'json5-ts-mode
                (keymap-set json5-ts-mode-map "C-c ${keys.code}" (cons "code" tessera-json-code-map))))
          '';
        })
      ]
    );
}
