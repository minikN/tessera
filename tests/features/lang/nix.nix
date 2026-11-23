{
  lib,
  expect,
  check,
  ...
}:

{
  emacs = check {
    platform = "darwin";
    features = {
      emacs.enable = true;
      emacs.eglot.enable = true;
      nix.enable = true;
    };
    assertions =
      { home, ... }:
      let
        packages = home.programs.emacs.finalPackage.explicitRequires;
        package = lib.findFirst (p: p.pname or "" == "tessera-nix") null packages;
        source = builtins.readFile package.src;
      in
      [
        {
          assertion = lib.any (p: p.pname or "" == "polymode") packages;
          message = "nix installs polymode";
        }
        {
          assertion = lib.hasInfix "(define-polymode tessera-nix-polymode" source;
          message = "nix defines its polymode";
        }
        {
          assertion = lib.hasInfix "(require 'nix-ts-mode)" source;
          message = "nix loads its tree-sitter host mode";
        }
        {
          assertion = lib.hasInfix ":language-id \"nix\"" source;
          message = "nix registers nil with Eglot";
        }
        {
          assertion = lib.hasInfix "(:nil (:formatting (:command [" source;
          message = "nil formats with nixfmt";
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
        nix.enable = true;
      };
    messages = [ "features.nix: features.emacs.package is built without tree-sitter" ];
  };
}
