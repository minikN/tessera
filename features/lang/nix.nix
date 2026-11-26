{
  lib,
  mkFeature,
  mkElispConfig,
  ...
}:

mkFeature {
  name = "nix";

  doc = {
    summary = "Nix development environment";
    description = ''
      Sets the editor up for Nix.

      - `packages.nil.package` provides the language server
      - `packages.nixfmt.package` formats through the language server

      ```nix
      features.nix.enable = true;
      ```

      ## With Emacs

      - `nix-ts-mode` provides syntax highlighting and indentation. Its grammar
        comes with this feature, so Emacs never asks to install it
      - `features.emacs.treesit` enables Combobulate in Nix tree-sitter buffers
      - Eglot starts nil when the emacs.eglot feature is enabled. Formatting
        uses nixfmt
      - polymode gives indented strings tagged with a language their own major
        mode. Put the tag in a comment immediately before the opening quotes;
        for example, `# elisp` selects `emacs-lisp-mode`, and `# bash` selects
        `sh-mode`. Other language tags work when their modes are available
      - if `features.emacs.package` is built without tree-sitter, Nix files use
        `nix-mode` and home-manager prints a warning. Polymode and the language
        server still work
    '';
  };

  options =
    { pkgs, ... }:
    {
      packages = {
        nil.package = lib.mkPackageOption pkgs "nil" {
          extraDescription = "Provides the Nix language server.";
        };
        nixfmt.package = lib.mkPackageOption pkgs "nixfmt" {
          extraDescription = "Formats Nix through the language server.";
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
      cfg = config.features.nix;
      inherit (config.features) emacs;
      treesit = emacs.package.withTreeSitter or false;
    in
    lib.mkIf emacs.enable (
      lib.mkMerge [
        {
          warnings = lib.optional (
            !treesit
          ) "features.nix: features.emacs.package is built without tree-sitter; Nix files use nix-mode.";
        }

        (mkElispConfig pkgs {
          name = "tessera-nix";
          summary = "Nix";
          elispPackages =
            epkgs:
            with epkgs;
            [
              nix-mode
              polymode
            ]
            ++ lib.optionals treesit [
              nix-ts-mode
              (treesit-grammars.with-grammars (g: with g; [ tree-sitter-nix ]))
            ];

          config = # elisp
            ''
              (eval-and-compile
                (require 'polymode))
              (require '${if treesit then "nix-ts-mode" else "nix-mode"})

              (define-hostmode tessera-nix-hostmode
                :mode '${if treesit then "nix-ts-mode" else "nix-mode"})

              (define-auto-innermode tessera-nix-dynamic-innermode
                :head-matcher (cons "^.*\\(#[[:blank:]]+[[:alnum:]_+-]+\n[[:blank:]]*'''\\)" 1)
                :tail-matcher "^[ \t]*'''[ \t]*)?;?[ \t]*$"
                :mode-matcher (cons "#[[:blank:]]+\\([[:alnum:]_+-]+\\)" 1)
                :body-indent-offset 4
                :head-mode 'host
                :tail-mode 'host)

              (define-polymode tessera-nix-polymode
                :hostmode 'tessera-nix-hostmode
                :innermodes '(tessera-nix-dynamic-innermode))

              (add-to-list 'auto-mode-alist '("\\.nix\\'" . tessera-nix-polymode))

              ${lib.optionalString (treesit && config.features.emacs.treesit.enable) ''
                (declare-function combobulate-mode "combobulate")
                (add-hook 'nix-ts-mode-hook #'combobulate-mode)
              ''}
              ${lib.optionalString config.features.emacs.eglot.enable ''
                (defun tessera-nix--workspace-configuration (_server)
                  "Return nil's settings, including the nixfmt executable."
                  '(:nil (:formatting (:command ["${cfg.packages.nixfmt.package}/bin/nixfmt"]))))

                (with-eval-after-load 'eglot
                  (add-to-list 'eglot-server-programs
                               '(((nix-mode :language-id "nix")
                                  (nix-ts-mode :language-id "nix"))
                                 . ("${cfg.packages.nil.package}/bin/nil")))
                  (add-hook 'tessera-eglot-workspace-configuration-functions
                            #'tessera-nix--workspace-configuration))

                (defun tessera-nix--eglot-ensure ()
                  "Start Eglot in Nix buffers."
                  (require 'eglot)
                  ;; tree-sitter does this way better than the lsp
                  (setq-local eglot-stay-out-of (cons 'imenu eglot-stay-out-of))
                  (eglot-ensure))
                (add-hook 'nix-mode-hook #'tessera-nix--eglot-ensure)
                ${lib.optionalString treesit ''
                  (add-hook 'nix-ts-mode-hook #'tessera-nix--eglot-ensure)
                ''}
              ''}
            '';
        })
      ]
    );
}
