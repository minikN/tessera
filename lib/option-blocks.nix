{ lib }:

## The blocks (`nixos`, `darwin`, `home`, `globals`) of a feature's source that
## refer to its option `path` (relative to the feature, e.g. "daemon.enable").
file: name: path:
let
  own = "config\\.features\\.${lib.escapeRegex (lib.concatStringsSep "." (lib.toList name))}";

  ## Top-level attributes of the mkFeature call are indented by two spaces.
  blocks = (lib.foldl'
    (acc: line:
      let start = builtins.match "  ([A-Za-z]+) =.*" line;
          current = if start == null then acc.current else builtins.head start;
      in { inherit current; texts = acc.texts // { ${current} = (acc.texts.${current} or "") + line + "\n"; }; })
    { current = "_"; texts = { }; }
    (lib.splitString "\n" (builtins.readFile file))).texts;

  p = lib.escapeRegex path;
  found = re: text: builtins.length (builtins.split re text) > 1;
  refers = text:
    found "\\.${p}([^A-Za-z0-9_'-]|$)" text
    || (found "with ${own};" text && found "(^|[^A-Za-z0-9_.'-])${p}([^A-Za-z0-9_'-]|$)" text);
in
builtins.filter (b: blocks ? ${b} && refers blocks.${b}) [ "nixos" "darwin" "home" "globals" ]
