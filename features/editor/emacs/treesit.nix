{
  lib,
  mkFeature,
  mkElispConfig,
  ...
}:

mkFeature {
  name = [
    "emacs"
    "treesit"
  ];

  doc = {
    summary = "Structural navigation and editing with tree-sitter";
    description = ''
      Installs and configures Combobulate, including Tessera's JSON5 and Nix
      language definitions. Language features enable it in their supported
      tree-sitter modes and continue to provide the grammars. Currently those
      are JavaScript, TypeScript, TSX, JSON, JSON5 and Nix. The JSON5 and Nix
      extensions are installed only with their respective language features.

      ```nix
      features.emacs.treesit.enable = true;
      ```

      This feature needs `features.emacs.package` built with tree-sitter. It
      enhances the usual structural navigation and editing commands rather than
      replacing Tessera's keymaps. `C-c c o` holds Combobulate's own commands;
      `C-c c o o` opens its transient menu. With `emacs.keymaps`, all prefixes
      and commands under `C-c c o`, including envelope templates, have
      which-key descriptions.

      | Keys | Command |
      |------|---------|
      | `C-M-u`, `C-M-d` | navigate to the parent, or into a child |
      | `C-M-n`, `C-M-p` | navigate to the next or previous sibling |
      | `C-M-a`, `C-M-e`, `C-M-h` | go to or mark the surrounding definition |
      | `M-a`, `M-e` | navigate to the previous or next logical node |
      | `M-n`, `M-p` | navigate between paired sequences, such as JSX tags |
      | `M-h` | expand the region structurally |
      | `M-k` | kill the node at point |
      | `C-M-t` | transpose structural expressions |
      | `M-P`, `M-N` | drag the node to the previous or next sibling position |
      | `M-<left>`, `M-<right>` | splice the node itself, or its whole parent |
      | `M-<up>`, `M-<down>` | splice what precedes or follows point into the parent |
      | `M-(` | wrap the expression at point in parentheses |

      In JSX and TSX, typing `>` closes an opening tag automatically. Within a
      parsed opening tag, typing `=` after an attribute starts a template for its
      value: a string, expression or expression object, with `TAB` cycling through
      the choices. `className` defaults to a string, `style` to an expression
      object and `ref` to an expression. Other attributes offer all three choices.
      If tree-sitter does not recognize an opening tag, `=` inserts normally.
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
      treesit = config.features.emacs.package.withTreeSitter or false;
    in
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = treesit;
            message = "features.emacs.treesit needs features.emacs.package built with tree-sitter.";
          }
        ];
      }

      (lib.mkIf treesit (
        mkElispConfig pkgs {
          name = "tessera-treesit";
          summary = "Structural navigation and editing with tree-sitter";
          elispPackages =
            epkgs:
            [
              (pkgs.tessera.emacs.combobulate.override { emacsPackages = epkgs; })
            ]
            ++ lib.optionals config.features.json.enable [
              (pkgs.tessera.emacs.combobulate-json5.override { emacsPackages = epkgs; })
            ]
            ++ lib.optionals config.features.nix.enable [
              (pkgs.tessera.emacs.combobulate-nix.override { emacsPackages = epkgs; })
            ];

          config = # elisp
            ''
              (defvar combobulate-key-prefix)
              (setq combobulate-key-prefix "C-c ${keys.code} o")
              (require 'combobulate)

              ${lib.optionalString config.features.json.enable ''
                (require 'tessera-combobulate-json5)
              ''}
              ${lib.optionalString config.features.nix.enable ''
                (require 'tessera-combobulate-nix)
              ''}

              ${lib.optionalString config.features.emacs.keymaps.enable ''
                (declare-function tessera-keymaps-describe-key "tessera-keymaps")

                (defun tessera-combobulate--describe-envelope (&rest args)
                  "Add which-key descriptions to the envelope bindings defined by ARGS."
                  (tessera-keymaps-describe-key
                   (combobulate-read envelope-map)
                   (plist-get args :key) (plist-get args :description))
                  (when (plist-get args :extra-key)
                    (tessera-keymaps-describe-key
                     (combobulate-read map)
                     (plist-get args :extra-key) (plist-get args :description))))

                (with-eval-after-load 'tessera-keymaps
                (advice-add 'combobulate-define-envelope :after
                            #'tessera-combobulate--describe-envelope)

                (tessera-keymaps-describe-key combobulate-options-key-map
                                                    "o" "open command menu")
                (tessera-keymaps-describe-key combobulate-options-key-map
                                                    "c" "clone node")
                (tessera-keymaps-describe-key combobulate-options-key-map
                                                    "t" "bulk edit")
                (tessera-keymaps-describe-key combobulate-options-key-map
                                                    "x" "xref")
                (tessera-keymaps-describe-key combobulate-options-key-map
                                                    "h" "highlight")
                (tessera-keymaps-describe-key combobulate-options-key-map
                                                    "B" "query builder")

                (tessera-keymaps-describe-key combobulate-cursor-edit-key-map
                                                    "c" "edit sequence")
                (tessera-keymaps-describe-key combobulate-cursor-edit-key-map
                                                    "t" "edit nodes by type")
                (tessera-keymaps-describe-key combobulate-cursor-edit-key-map
                                                    "x" "edit nodes by text")
                (tessera-keymaps-describe-key combobulate-cursor-edit-key-map
                                                    "s" "edit sibling nodes")
                (tessera-keymaps-describe-key combobulate-cursor-edit-key-map
                                                    "q" "edit query matches")

                (tessera-keymaps-describe-key combobulate-xref-key-map
                                                    "b" "find query references in buffer")

                (tessera-keymaps-describe-key combobulate-highlight-key-map
                                                    "h" "highlight node at point")
                (tessera-keymaps-describe-key combobulate-highlight-key-map
                                                    "q" "highlight query matches")
                (tessera-keymaps-describe-key combobulate-highlight-key-map
                                                    "c" "clear highlights")

                (tessera-keymaps-describe-key combobulate-query-key-map
                                                    "q" "open query builder")
                (tessera-keymaps-describe-key combobulate-query-key-map
                                                    "p" "build match query for node at point")
                (tessera-keymaps-describe-key combobulate-query-key-map
                                                    "r" "build query from root to point")

                (dolist (registration combobulate-registered-languages-alist)
                  (let* ((language (car registration))
                         (map (symbol-value (combobulate-get 'map language)))
                         (envelope-map (symbol-value (combobulate-get 'envelope-map language)))
                         (key (concat combobulate-key-prefix " e")))
                    (keymap-set map key envelope-map)
                    (tessera-keymaps-describe-key map key "envelop")))

                (tessera-keymaps-describe-key combobulate-key-map
                                               combobulate-key-prefix "combobulate"))
              ''}

              ;; These optional highlighting queries target older grammars.
              (setq combobulate-javascript-highlight-queries-default nil
                    combobulate-typescript-highlight-queries-default nil
                    combobulate-tsx-highlight-queries-default nil)
            '';
        }
      ))
    ];
}
