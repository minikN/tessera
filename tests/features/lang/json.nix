{ platform, expect, ... }:

{
  without-tree-sitter = expect {
    platform = platform;
    features =
      { pkgs, ... }:
      {
        emacs.enable = true;
        emacs.package = pkgs.emacs.override { withTreeSitter = false; };
        json.enable = true;
      };
    messages = [ "features.json: features.emacs.package is built without tree-sitter" ];
  };
}
