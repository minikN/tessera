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
        through go to definition (e.g. libraries) are managed too.

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
      | `M-g f` | diagnostics (with the completion feature) |
      | `C-c c a` | code actions |
      | `C-c c f` | format the region or buffer |
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

          (defvar-keymap tessera-eglot-map
            :doc "Keymap of Eglot commands for the buffers it manages."
            "a" #'eglot-code-actions
            "f" #'eglot-format
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
