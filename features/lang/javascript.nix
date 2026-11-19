{
  lib,
  mkFeature,
  mkElispConfig,
  ...
}:

mkFeature {
  name = "javascript";

  doc = {
    summary = "JavaScript and TypeScript development environment";
    description = ''
      Sets the editor up for JavaScript and TypeScript. Doesn't install any
      runtime or package manager globally.

      | | JavaScript | TypeScript | TSX |
      |---|---|---|---|
      | Files | `.js`, `.jsx`, `.mjs`, `.cjs` | `.ts`, `.mts`, `.cts` | `.tsx` |
      | Language server | typescript-language-server, `deno lsp` in Deno projects | typescript-language-server, `deno lsp` in Deno projects | typescript-language-server, `deno lsp` in Deno projects |
      | Formatting | the project's Biome, oxfmt or ESLint, else the language server | the project's Biome, oxfmt or ESLint, else the language server | the project's Biome, oxfmt or ESLint, else the language server |
      | Linting | the language server, the project's ESLint and Biome | the language server, the project's ESLint and Biome | the language server, the project's ESLint and Biome |

      - two spaces, in JavaScript like in TypeScript
      - typescript-language-server (`packages.tsls.package`). It
        uses the TypeScript of the project's `node_modules`, or its own if
        there is none. In Deno projects, those with a `deno.json` or
        `deno.jsonc` in the file's directory or above, it is `deno lsp` of
        `packages.deno.package` instead

      ```nix
      features.javascript = {
        enable = true;
        utils.enable = true;
        packages.npm.package = pkgs.nodejs_22;
      };
      ```

      ## With Emacs

      - the modes are the tree-sitter modes that ship with Emacs. The
        grammars come with this feature, so Emacs never asks to install them
      - Eglot starts the language server when the emacs.eglot feature is enabled
      - it supports the following runtimes: `node`, `deno` and `bun`
      - it supports the following package managers: `npm`, `pnpm`, `yarn`,
        `deno`, `bun`
      - it supports the following formatters: `eslint`, `biome` and `oxfmt`. If the
        project sets one up, found by its configuration file in the file's
        directory or above, its language server runs next to typescript-language-server
        (or `deno lsp`) through rassumfrassum
      - `eglot-format` will use the formatter's LSP to format the document if one is
         defined. If not, it's routed through tsls (or `deno lsp`) as a fallback
      - formatters are the project's own (`node_modules/.bin`) if it has
        them, otherwise the ones from nixpkgs
      - if `features.emacs.package` is built without
        tree-sitter, JavaScript and TypeScript files open in `js-mode` (`.jsx`
        and `.tsx` in `js-jsx-mode`) and home-manager prints a warning. The
        language server then treats TypeScript as JavaScript

      ## Utility package

      `utils.enable` adds tessera's javascript-utils package, with
      refactorings and commands for the package manager. With the keymaps
      feature, `C-c c u` holds the refactorings in JavaScript and TypeScript
      buffers (with tree-sitter). They complement the
      language server's refactorings, which are code actions (`C-c c a`,
      emacs.eglot), and its source actions for the whole buffer, such as
      fix all or add missing imports (`C-c c s`, emacs.eglot). They work
      like their js2-refactor namesakes:

      | Keys | Refactoring |
      |------|-------------|
      | `C-c c u t` | ternary in a `return`, assignment or declaration to `if` |
      | `C-c c u l`, `C-c c u d` | log the expression at point (`console.log`, `debug`) |
      | `C-c c u s` | split the string at point, or join it again |
      | `C-c c u v` | split a declaration of several variables |
      | `C-c c u x`, `C-c c u c` | one element per line, or all on one line |
      | `C-c c u p`, `C-c c u P` | expression to parameter, parameter to local variable |
      | `C-c c u a` | toggle `async` |
      | `C-c c u k` | kill to the end of the line, the list or the block |
      | `C-c c u >`, `C-c c u <` | move the next statement into the block, or the last one out; repeat with `>`/`<` |
      | `C-c c u u` | replace the surrounding statement with the one at point |
      | `C-c c u o` | wrap in a `for … of` loop |
      | `C-c c u j` | copy the path of the object value at point, e.g. `a.b[2]` |

      `C-c c p` holds commands for the package the current buffer belongs
      to (any buffer: files, dired, …), run by the package's own tool, so
      it works with Node.js, Bun and Deno alike. The package is the nearest
      directory with a `package.json`, `deno.json` or `deno.jsonc`; its tool
      comes from the `packageManager` field of `package.json`, then a
      `deno.json(c)`, then the nearest lockfile (`bun.lock(b)`,
      `pnpm-lock.yaml`, `yarn.lock`, `package-lock.json`); npm otherwise.

      | Keys | Command | e.g. with Bun |
      |------|---------|---------------|
      | `C-c c p r` | run a script or task | `bun run build` |
      | `C-c c p i` | install the dependencies | `bun install` |
      | `C-c c p a`, `C-c c p d` | add packages, as development dependencies | `bun add --dev x` |
      | `C-c c p u` | remove packages | `bun remove x` |
      | `C-c c p v` | visit `package.json` or `deno.json` | |

      Executables can be changed via the `packages` option. Tools, lockfiles and commands can be changed with
      `M-x customize-group tessera-javascript-utils`.
    '';
  };

  options =
    { pkgs, ... }:
    let
      tool = package: lib.mkPackageOption pkgs package { };
    in
    {
      packages = {
        tsls.package = tool "typescript-language-server";
        npm.package = lib.mkPackageOption pkgs "nodejs" {
          extraDescription = "Provides npm, and Node.js for the scripts of npm and pnpm and for the project's own Biome and oxfmt.";
        };
        pnpm.package = tool "pnpm";
        yarn.package = tool "yarn";
        bun.package = tool "bun";
        deno.package = lib.mkPackageOption pkgs "deno" {
          extraDescription = "Also the language server of Deno projects.";
        };
      };

      utils.enable = lib.mkEnableOption "javascript-utils, refactorings and package manager commands for Emacs";
    };

  home =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.features.javascript;
      inherit (config.features) emacs;
      inherit (emacs.keymaps) keys;
      treesit = emacs.package.withTreeSitter or false;
      rassPreset = pkgs.writeText "tessera-javascript.py" ''
        """Tessera's JavaScript preset for rassumfrassum.

        The servers come from the command line: Deno's or
        typescript-language-server first, then those of the project's tools in
        the order they format.
        """

        from rassumfrassum.presets.tessera import Logic as TesseraLogic
        from rassumfrassum.presets.tslint import TypeScriptLogic


        class Logic(TesseraLogic, TypeScriptLogic):
            async def on_client_response(self, method, request_params, response_payload, is_error, server):
                await super().on_client_response(method, request_params, response_payload, is_error, server)
                # Let ESLint format the projects that don't have a formatter
                if method == "workspace/configuration" and not is_error and "eslint" in server.name.lower():
                    for item in response_payload:
                        if isinstance(item, dict) and "validate" in item:
                            item["format"] = True


        def logic_class():
            return Logic
      '';
    in
    lib.mkIf emacs.enable (
      lib.mkMerge [
        {
          warnings =
            lib.optional (!treesit)
              "features.javascript: features.emacs.package is built without tree-sitter; JavaScript and TypeScript files use js-mode.";
        }

        # TODO: Bun projects: format with `bun fmt` (C-c c f) and lint with
        # `bun lint` (a Flymake backend), like Deno projects get `deno lsp`.
        # `bun fmt` is in Bun 1.4.4; `bun lint` is canary-only there and lands
        # in release builds after oven-sh/bun#46439. Wait until nixpkgs' bun
        # has both (it is 1.4.2 as of 2026-11-09).
        (mkElispConfig pkgs {
          name = "tessera-javascript";
          summary = "JavaScript and TypeScript";
          elispPackages =
            epkgs:
            lib.optional cfg.utils.enable (
              pkgs.tessera.emacs.javascript-utils.override {
                emacsPackages = epkgs;
                nodejs = cfg.packages.npm.package;
                pnpm = cfg.packages.pnpm.package;
                yarn = cfg.packages.yarn.package;
                bun = cfg.packages.bun.package;
                deno = cfg.packages.deno.package;
              }
            )
            ++ lib.optional treesit (
              epkgs.treesit-grammars.with-grammars (
                g: with g; [
                  tree-sitter-javascript
                  tree-sitter-typescript
                  tree-sitter-tsx
                  tree-sitter-jsdoc
                ]
              )
            );

          config = ''
            ${
              if treesit then
                ''
                  (add-to-list 'auto-mode-alist '("\\.[cm]js\\'" . javascript-mode))
                  (add-to-list 'auto-mode-alist '("\\.[cm]ts\\'" . typescript-ts-mode))
                  (setopt treesit-enabled-modes
                          (if (eq treesit-enabled-modes t)
                              t
                            (seq-union treesit-enabled-modes '(js-ts-mode))))
                ''
              else
                ''
                  (add-to-list 'auto-mode-alist '("\\.[cm]?[jt]s\\'" . js-mode))
                  (add-to-list 'auto-mode-alist '("\\.[jt]sx\\'" . js-jsx-mode))
                ''
            }
            (setopt js-indent-level 2)
            ${lib.optionalString config.features.emacs.eglot.enable ''

              (defun tessera-javascript--project-command (command)
                "Return COMMAND, with the project's own program if it has one.
              That is the program of the same name in node_modules/.bin, run with
              Node.js first in `PATH'."
                (let ((bin (concat "node_modules/.bin/" (file-name-nondirectory (car command)))))
                  (if-let* ((dir (locate-dominating-file default-directory bin)))
                      `("${pkgs.coreutils}/bin/env"
                        ,(concat "PATH=${cfg.packages.npm.package}/bin:" (getenv "PATH"))
                        ,(file-local-name (expand-file-name bin dir))
                        ,@(cdr command))
                    command)))

              (defconst tessera-javascript--tool-servers
                '((("biome.json" "biome.jsonc" ".biome.json" ".biome.jsonc")
                   "${pkgs.biome}/bin/biome" "lsp-proxy")
                  ((".oxfmtrc.json" ".oxfmtrc.jsonc" "oxfmt.config.ts")
                   "${pkgs.oxfmt}/bin/oxfmt" "--lsp")
                  (("eslint.config.js" "eslint.config.mjs" "eslint.config.cjs"
                    "eslint.config.ts" "eslint.config.mts" "eslint.config.cts"
                    ".eslintrc.js" ".eslintrc.cjs" ".eslintrc.yaml" ".eslintrc.yml"
                    ".eslintrc.json" ".eslintrc")
                   "${pkgs.vscode-langservers-extracted}/bin/vscode-eslint-language-server" "--stdio"))
                "Language servers of the tools, after their configuration files.
              In the order they format.")

              (defun tessera-javascript--language-server (&rest _)
                "Return the language servers for the current buffer.
              Deno projects get Deno's, others typescript-language-server, with the
              servers of the tools the project sets up, see `tessera-eglot-contact'."
                (tessera-eglot-contact
                 (cons (if (or (locate-dominating-file default-directory "deno.json")
                               (locate-dominating-file default-directory "deno.jsonc"))
                           '("${cfg.packages.deno.package}/bin/deno" "lsp")
                         '("${cfg.packages.tsls.package}/bin/typescript-language-server" "--stdio"))
                       (seq-keep (pcase-lambda (`(,files . ,command))
                                   (and (seq-some (lambda (file) (locate-dominating-file default-directory file))
                                                  files)
                                        (tessera-javascript--project-command command)))
                                 tessera-javascript--tool-servers))
                 "${rassPreset}"))

              (with-eval-after-load 'eglot
                (add-to-list 'eglot-server-programs
                             '(((js-mode :language-id "javascript")
                                (js-ts-mode :language-id "javascript")
                                (tsx-ts-mode :language-id "typescriptreact")
                                (typescript-ts-mode :language-id "typescript"))
                               . tessera-javascript--language-server))
                (add-hook 'tessera-eglot-workspace-configuration-functions
                          #'tessera-javascript--workspace-configuration))

              (defun tessera-javascript--workspace-configuration (_server)
                "Type-check JavaScript outside projects with a jsconfig.json or tsconfig.json."
                '(:implicitProjectConfiguration (:checkJs t)))

              (defun tessera-javascript--eglot-ensure ()
                "Start Eglot, except in JSON buffers."
                (unless (derived-mode-p 'js-json-mode)
                  (require 'eglot)
                  ;; tree-sitter does this way better than the lsp
                  (setq-local eglot-stay-out-of (cons 'imenu eglot-stay-out-of))
                  (eglot-ensure)))
              (add-hook 'js-base-mode-hook #'tessera-javascript--eglot-ensure)
              (add-hook 'typescript-ts-base-mode-hook #'tessera-javascript--eglot-ensure)
            ''}
          '';
        })

        (lib.mkIf cfg.utils.enable {
          programs.emacs.extraConfig = ''
            (with-eval-after-load 'tessera-keymaps
              (require 'tessera-javascript-utils)
              (add-to-list 'tessera-code-package-maps
                           (cons #'tessera-javascript-utils-package-root
                                 tessera-javascript-utils-package-map))
              ${lib.optionalString treesit ''
                (defvar-keymap tessera-javascript-code-map
                  :doc "Keymap under `C-c c' in JavaScript and TypeScript buffers."
                  "u" (cons "utils" tessera-javascript-utils-refactor-map))
                (with-eval-after-load 'js
                  (keymap-set js-ts-mode-map "C-c ${keys.code}" (cons "code" tessera-javascript-code-map)))
                (with-eval-after-load 'typescript-ts-mode
                  (keymap-set typescript-ts-base-mode-map "C-c ${keys.code}"
                              (cons "code" tessera-javascript-code-map)))
              ''})
          '';
        })
      ]
    );
}
