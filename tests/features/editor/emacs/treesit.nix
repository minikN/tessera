{
  lib,
  expect,
  check,
  ...
}:

let
  packages = home: home.programs.emacs.finalPackage.explicitRequires;
  package =
    home: name: lib.findFirst (p: p.pname or "" == name) (throw "No ${name} package") (packages home);
  source = home: name: builtins.readFile (package home name).src;
in
{
  wiring = check {
    platform = "darwin";
    features = {
      emacs.enable = true;
      emacs.eglot.enable = true;
      emacs.keymaps.enable = true;
      emacs.treesit.enable = true;
      javascript.enable = true;
      json.enable = true;
      nix.enable = true;
    };
    assertions =
      { home, ... }:
      let
        treesitSource = source home "tessera-treesit";
        javascriptSource = source home "tessera-javascript";
        jsonSource = source home "tessera-json";
        nixSource = source home "tessera-nix";
        eglotSource = source home "tessera-eglot";
      in
      [
        {
          assertion = lib.any (p: p.pname or "" == "combobulate") (packages home);
          message = "treesit installs Combobulate";
        }
        {
          assertion = lib.hasInfix "(setq combobulate-key-prefix \"C-c c o\")" treesitSource;
          message = "Combobulate uses the code prefix";
        }
        {
          assertion = lib.hasInfix "(cons \"combobulate\" combobulate-options-key-map)" treesitSource;
          message = "Combobulate's prefix has a which-key description";
        }
        {
          assertion = lib.hasInfix "combobulate-tsx-highlight-queries-default nil" treesitSource;
          message = "Incompatible optional TSX highlighting is disabled";
        }
        {
          assertion = lib.hasInfix "(add-hook 'js-ts-mode-hook #'combobulate-mode)" javascriptSource;
          message = "JavaScript enables Combobulate";
        }
        {
          assertion = lib.hasInfix "(add-hook 'typescript-ts-base-mode-hook #'combobulate-mode)" javascriptSource;
          message = "TypeScript and TSX enable Combobulate";
        }
        {
          assertion = lib.hasInfix "(add-hook 'json-ts-mode-hook #'combobulate-mode)" jsonSource;
          message = "JSON enables Combobulate";
        }
        {
          assertion = !(lib.hasInfix "combobulate" nixSource);
          message = "Nix does not enable unsupported Combobulate integration";
        }
        {
          assertion = !(lib.hasInfix "json5-ts-mode-hook #'combobulate-mode" jsonSource);
          message = "JSON5 does not enable unsupported Combobulate integration";
        }
        {
          assertion = lib.hasInfix "(keymap-set eglot-mode-map \"M-d\" #'tessera-eglot-next-doc)" eglotSource;
          message = "Eglot documentation navigation leaves M-n to Combobulate";
        }
      ];
  };

  disabled = check {
    platform = "darwin";
    features = {
      emacs.enable = true;
      javascript.enable = true;
      json.enable = true;
    };
    assertions =
      { home, ... }:
      [
        {
          assertion = !(lib.any (p: p.pname or "" == "combobulate") (packages home));
          message = "Combobulate is only installed with the treesit feature";
        }
        {
          assertion = !(lib.hasInfix "combobulate-mode" (source home "tessera-javascript"));
          message = "JavaScript only enables Combobulate with the treesit feature";
        }
        {
          assertion = !(lib.hasInfix "combobulate-mode" (source home "tessera-json"));
          message = "JSON only enables Combobulate with the treesit feature";
        }
      ];
  };

  without-tree-sitter = expect {
    platform = "darwin";
    features =
      { pkgs, ... }:
      {
        emacs.enable = true;
        emacs.package = pkgs.emacs.override { withTreeSitter = false; };
        emacs.treesit.enable = true;
      };
    messages = [ "features.emacs.treesit needs features.emacs.package built with tree-sitter" ];
  };
}
