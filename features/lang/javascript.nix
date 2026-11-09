{
  lib,
  mkFeature,
  mkElispConfig,
  ...
}:

mkFeature {
  name = "javascript";

  doc = {
    summary = "JavaScript and TypeScript editing, whatever the runtime";
    description = ''
      Sets the editor up for JavaScript and TypeScript, currently Emacs
      through the emacs feature. It installs no runtime, so Node.js, Bun or
      Deno come from the project (e.g. its dev shell) or `home.packages`.

      - **Modes:** `.js`, `.jsx`, `.mjs` and `.cjs` files open in `js-ts-mode`,
        `.ts`, `.mts` and `.cts` in `typescript-ts-mode` and `.tsx` in
        `tsx-ts-mode`, the tree-sitter modes that ship with Emacs. The
        grammars come with this feature, so Emacs never asks to install them
      - **Indentation:** two spaces, in JavaScript like in TypeScript
      - **Language server:** typescript-language-server (`languageServer.package`),
        started by Eglot when the emacs.eglot feature is enabled. It uses the
        TypeScript of the project's `node_modules`, or its own if there is none.
        It type-checks JavaScript too, so e.g. a missing import is an error
        with a fix; in a project with a `jsconfig.json` or `tsconfig.json`,
        that needs `"checkJs": true` there. In Deno projects, those with a
        `deno.json` or `deno.jsonc` in the file's directory or above, it is
        `deno lsp` of `packages.deno.package` instead, with Deno's linter
      - **Without tree-sitter:** if `features.emacs.package` is built without
        tree-sitter, JavaScript and TypeScript files open in `js-mode` (`.jsx`
        and `.tsx` in `js-jsx-mode`) and home-manager prints a warning. The
        language server then treats TypeScript as JavaScript

      `utils.enable` adds tessera's javascript-utils package, with
      refactorings and commands for the package manager. With the keymaps
      feature, `C-c c u` holds the refactorings in JavaScript and TypeScript
      buffers (with tree-sitter). They complement the
      language server's refactorings, which are code actions (`C-c c a`,
      emacs.eglot), and work like their js2-refactor namesakes:

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

      Commands run in a compilation buffer named after them, so several
      can run at once. Each tool runs from the Nix store (`packages`),
      never from `PATH`, so all five are in the closure. Scripts of npm and
      pnpm get the same Node.js, scripts of bun run on bun. Tools, lockfiles
      and commands can be changed with
      `M-x customize-group tessera-javascript-utils`.

      ```nix
      features.javascript = {
        enable = true;
        utils.enable = true;
        packages.npm.package = pkgs.nodejs_22;
      };
      ```
    '';
  };

  options =
    { pkgs, ... }:
    let
      tool = package: lib.mkPackageOption pkgs package { };
    in
    {
      languageServer.package = lib.mkPackageOption pkgs "typescript-language-server" { };

      packages = {
        npm.package = lib.mkPackageOption pkgs "nodejs" {
          extraDescription = "Provides npm, and Node.js for the scripts of npm and pnpm.";
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
              pkgs.tessera.javascript-utils.override {
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

            (defun tessera-javascript--language-server (&rest _)
              "Return the language server for the current buffer, Deno's in Deno projects."
              (if (or (locate-dominating-file default-directory "deno.json")
                      (locate-dominating-file default-directory "deno.jsonc"))
                  '("${cfg.packages.deno.package}/bin/deno" "lsp")
                '("${cfg.languageServer.package}/bin/typescript-language-server" "--stdio")))

            (with-eval-after-load 'eglot
              (add-to-list 'eglot-server-programs
                           '(((js-mode :language-id "javascript")
                              (js-ts-mode :language-id "javascript")
                              (tsx-ts-mode :language-id "typescriptreact")
                              (typescript-ts-mode :language-id "typescript"))
                             . tessera-javascript--language-server))
              ;; Type-check JavaScript outside projects with a jsconfig.json or tsconfig.json
              (setq-default eglot-workspace-configuration
                            (plist-put (default-value 'eglot-workspace-configuration)
                                       :implicitProjectConfiguration '(:checkJs t))))
            ${lib.optionalString config.features.emacs.eglot.enable ''

              (defun tessera-javascript--eglot-ensure ()
                "Start Eglot, except in JSON buffers."
                (unless (derived-mode-p 'js-json-mode)
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
                  "u" (cons "Utils" tessera-javascript-utils-refactor-map))
                (with-eval-after-load 'js
                  (keymap-set js-ts-mode-map "C-c ${keys.code}" (cons "Code" tessera-javascript-code-map)))
                (with-eval-after-load 'typescript-ts-mode
                  (keymap-set typescript-ts-base-mode-map "C-c ${keys.code}"
                              (cons "Code" tessera-javascript-code-map)))
              ''})
          '';
        })
      ]
    );
}
