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
  languageExtensions = {
    json = "combobulate-json5";
    nix = "combobulate-nix";
  };
  languageOnly =
    language:
    let
      extension = languageExtensions.${language};
      otherExtensions = lib.attrValues (removeAttrs languageExtensions [ language ]);
    in
    check {
      platform = "darwin";
      features = {
        emacs.enable = true;
        emacs.treesit.enable = true;
        ${language}.enable = true;
      };
      assertions =
        { home, ... }:
        let
          treesitSource = source home "tessera-treesit";
        in
        [
          {
            assertion = lib.any (p: p.pname or "" == extension) (packages home);
            message = "${language} installs ${extension}";
          }
          {
            assertion = lib.hasInfix "(require '${extension})" treesitSource;
            message = "${language} loads ${extension}";
          }
        ]
        ++ lib.concatMap (otherExtension: [
          {
            assertion = !(lib.any (p: p.pname or "" == otherExtension) (packages home));
            message = "${language} does not install ${otherExtension}";
          }
          {
            assertion = !(lib.hasInfix "(require '${otherExtension})" treesitSource);
            message = "${language} does not load ${otherExtension}";
          }
        ]) otherExtensions;
    };
in
lib.mapAttrs' (
  language: _: lib.nameValuePair "${language}-only" (languageOnly language)
) languageExtensions
// {
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
        keymapsSource = source home "tessera-keymaps";
        json5CombobulateSource = source home "combobulate-json5";
        nixCombobulateSource = source home "combobulate-nix";
        javascriptSource = source home "tessera-javascript";
        jsonSource = source home "tessera-json";
        nixSource = source home "tessera-nix";
        eglotSource = source home "tessera-eglot";
        commandDescriptions = [
          "\"o\" \"open command menu\""
          "\"c\" \"clone node\""
          "\"t\" \"bulk edit\""
          "\"x\" \"xref\""
          "\"h\" \"highlight\""
          "\"B\" \"query builder\""
          "\"c\" \"edit sequence\""
          "\"t\" \"edit nodes by type\""
          "\"x\" \"edit nodes by text\""
          "\"s\" \"edit sibling nodes\""
          "\"q\" \"edit query matches\""
          "\"b\" \"find query references in buffer\""
          "\"h\" \"highlight node at point\""
          "\"q\" \"highlight query matches\""
          "\"c\" \"clear highlights\""
          "\"q\" \"open query builder\""
          "\"p\" \"build match query for node at point\""
          "\"r\" \"build query from root to point\""
        ];
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
          assertion = lib.hasInfix "(defun tessera-keymaps-describe-key" keymapsSource;
          message = "The keymaps feature provides the shared description helper";
        }
        {
          assertion = lib.hasInfix "(with-eval-after-load 'tessera-keymaps" treesitSource;
          message = "Treesit loads descriptions through the keymaps integration";
        }
        {
          assertion = lib.hasInfix "combobulate-key-prefix \"combobulate\")" treesitSource;
          message = "Combobulate's prefix has a which-key description";
        }
        {
          assertion = lib.all (description: lib.hasInfix description treesitSource) commandDescriptions;
          message = "Every Combobulate command and submap has a which-key description";
        }
        {
          assertion = lib.hasInfix "(dolist (registration combobulate-registered-languages-alist)" treesitSource;
          message = "Every language's envelope prefix has a which-key description";
        }
        {
          assertion = lib.hasInfix "(keymap-set map key envelope-map)" treesitSource;
          message = "Envelope prefixes use Tessera's configured Combobulate prefix";
        }
        {
          assertion = lib.hasInfix "(advice-add 'combobulate-define-envelope :after" treesitSource;
          message = "Generated envelope commands have which-key descriptions";
        }
        {
          assertion = lib.hasInfix "combobulate-tsx-highlight-queries-default nil" treesitSource;
          message = "Incompatible optional TSX highlighting is disabled";
        }
        {
          assertion = lib.hasInfix "(require 'combobulate-json5)" treesitSource;
          message = "treesit loads the JSON5 extension";
        }
        {
          assertion = lib.hasInfix ":name json5" json5CombobulateSource;
          message = "The JSON5 package registers its Combobulate language";
        }
        {
          assertion = lib.hasInfix "(require 'combobulate-nix)" treesitSource;
          message = "treesit loads the Nix extension";
        }
        {
          assertion = lib.hasInfix ":name nix" nixCombobulateSource;
          message = "The Nix package registers its Combobulate language";
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
          assertion = lib.hasInfix "(add-hook 'nix-ts-mode-hook #'combobulate-mode)" nixSource;
          message = "Nix enables Combobulate";
        }
        {
          assertion = lib.hasInfix "(add-hook 'json5-ts-mode-hook #'combobulate-mode)" jsonSource;
          message = "JSON5 enables Combobulate";
        }
        {
          assertion = lib.hasInfix "(keymap-set eglot-mode-map \"M-d\" #'tessera-eglot-next-doc)" eglotSource;
          message = "Eglot documentation navigation leaves M-n to Combobulate";
        }
      ];
  };

  without-languages = check {
    platform = "darwin";
    features = {
      emacs.enable = true;
      emacs.treesit.enable = true;
    };
    assertions =
      { home, ... }:
      let
        treesitSource = source home "tessera-treesit";
      in
      [
        {
          assertion = lib.any (p: p.pname or "" == "combobulate") (packages home);
          message = "treesit installs Combobulate without language features";
        }
        {
          assertion =
            !(lib.any (p: lib.elem (p.pname or "") (lib.attrValues languageExtensions)) (packages home));
          message = "No Combobulate extensions are installed without language features";
        }
        {
          assertion = lib.all (extension: !(lib.hasInfix "(require '${extension})" treesitSource)) (
            lib.attrValues languageExtensions
          );
          message = "No Combobulate extensions are loaded without language features";
        }
      ];
  };

  without-keymaps = check {
    platform = "darwin";
    features = {
      emacs.enable = true;
      emacs.keymaps.enable = false;
      emacs.treesit.enable = true;
      json.enable = true;
      nix.enable = true;
    };
    assertions =
      { home, ... }:
      let
        treesitSource = source home "tessera-treesit";
      in
      [
        {
          assertion = !(lib.any (p: p.pname or "" == "tessera-keymaps") (packages home));
          message = "Treesit does not install the keymaps package";
        }
        {
          assertion = !(lib.hasInfix "tessera-keymaps-describe-key" treesitSource);
          message = "Treesit does not call the keymaps helper when keymaps are disabled";
        }
        {
          assertion = !(lib.hasInfix "tessera-combobulate--describe-envelope" treesitSource);
          message = "Treesit does not install envelope descriptions when keymaps are disabled";
        }
        {
          assertion = lib.hasInfix "(setq combobulate-key-prefix \"C-c c o\")" treesitSource;
          message = "Combobulate keeps its command prefix when keymaps are disabled";
        }
      ];
  };

  disabled = check {
    platform = "darwin";
    features = {
      emacs.enable = true;
      javascript.enable = true;
      json.enable = true;
      nix.enable = true;
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
          message = "JSON and JSON5 only enable Combobulate with the treesit feature";
        }
        {
          assertion = !(lib.hasInfix "combobulate-mode" (source home "tessera-nix"));
          message = "Nix only enables Combobulate with the treesit feature";
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
