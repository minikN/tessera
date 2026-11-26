{ platform, expect, ... }:

{
  without-tree-sitter = expect {
    platform = platform;
    features =
      { pkgs, ... }:
      {
        emacs.enable = true;
        emacs.package = pkgs.emacs.override { withTreeSitter = false; };
        javascript.enable = true;
      };
    messages = [ "features.javascript: features.emacs.package is built without tree-sitter" ];
  };
}
