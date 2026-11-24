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
      Installs and configures Combobulate. Language features enable it in their
      supported tree-sitter modes and continue to provide the grammars. Currently
      those are JavaScript, TypeScript, TSX and JSON. JSON5 and Nix are not
      supported by Combobulate.

      ```nix
      features.emacs.treesit.enable = true;
      ```

      This feature needs `features.emacs.package` built with tree-sitter. It
      enhances the usual structural navigation and editing commands rather than
      replacing Tessera's keymaps. `C-c c o` holds Combobulate's own commands;
      `C-c c o o` opens its transient menu.

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
          elispPackages = epkgs: [
            (pkgs.tessera.emacs.combobulate.override { emacsPackages = epkgs; })
          ];

          config = # elisp
            ''
              (defvar combobulate-key-prefix)
              (setq combobulate-key-prefix "C-c ${keys.code} o")
              (require 'combobulate)
              ;; These optional highlighting queries target older grammars.
              (setq combobulate-javascript-highlight-queries-default nil
                    combobulate-typescript-highlight-queries-default nil
                    combobulate-tsx-highlight-queries-default nil)
              (keymap-set combobulate-key-map combobulate-key-prefix
                          (cons "combobulate" combobulate-options-key-map))
            '';
        }
      ))
    ];
}
