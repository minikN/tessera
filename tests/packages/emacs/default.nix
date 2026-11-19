{ lib, pkgs }:

## Byte-compiles `pkgs.tessera.emacs.<name>` with warnings as errors (its
## build ignores them) and runs the ERT tests in `<name>.el` against it,
## with `PATH` stripped to the system's own tools and once per shell in
## `shells` as `shell-file-name`.
let
  ert =
    name:
    {
      grammars,
      elispPackages ? _: [ ],
      shells ? [ "/bin/sh" ],
    }:
    let
      epkgs = pkgs.emacs-nox.pkgs;
      package = pkgs.tessera.emacs.${name}.override { emacsPackages = epkgs; };
      emacs = epkgs.withPackages (
        [
          package
          (epkgs.treesit-grammars.with-grammars grammars)
        ]
        ++ elispPackages epkgs
      );
    in
    pkgs.runCommandLocal "test-${name}" { } ''
      export HOME=$TMPDIR
      cp ${package}/share/emacs/site-lisp/elpa/*/tessera-${name}.el $TMPDIR
      chmod u+w $TMPDIR/tessera-${name}.el
      ${emacs}/bin/emacs --batch --eval '(package-activate-all)' \
        --eval '(setq byte-compile-error-on-warn t)' \
        -f batch-byte-compile $TMPDIR/tessera-${name}.el
      export PATH=/usr/bin:/bin
      ${lib.concatMapStrings (shell: ''
        echo "shell-file-name: ${shell}"
        ${emacs}/bin/emacs --batch --eval '(package-activate-all)' \
          --eval '(setq shell-file-name "${shell}")' \
          -l ert -l ${./${name}.el} -f ert-run-tests-batch-and-exit
      '') shells}
      touch $out
    '';
in
{
  javascript-utils = ert "javascript-utils" {
    grammars = g: [
      g.tree-sitter-javascript
      g.tree-sitter-typescript
      g.tree-sitter-tsx
      g.tree-sitter-jsdoc
    ];
    shells = [
      "/bin/sh"
      "${pkgs.zsh}/bin/zsh"
    ];
  };

  json-utils = ert "json-utils" {
    grammars = g: [
      g.tree-sitter-json
      g.tree-sitter-json5
    ];
    elispPackages = epkgs: [ epkgs.json5-ts-mode ];
  };
}
