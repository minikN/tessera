{ lib }:

## Parses a module and collects all the `globals` and `features` it reads.
file: name:
let
  src = builtins.readFile file;
  ident = "[A-Za-z_][A-Za-z0-9_'-]*";
  captures = re: builtins.filter builtins.isList (builtins.split re src);

  direct = map (m: builtins.elemAt m 0)
    (captures "config\\.((globals|features)(\\.${ident})+)");

  inherited = lib.concatMap
    (m: map (n: "${builtins.elemAt m 0}.${n}")
      (builtins.filter (n: builtins.isString n && n != "")
        (builtins.split "[[:space:]]+" (builtins.elemAt m 3))))
    (captures "inherit \\(config\\.((globals|features)(\\.${ident})*)\\)([^;]*);");

  own = "features.${lib.concatStringsSep "." (lib.toList name)}";
  paths = lib.unique (builtins.filter (p: p != own && !lib.hasPrefix "${own}." p)
    (direct ++ inherited));
in
lib.sort lib.lessThan
  (builtins.filter (p: !lib.any (q: lib.hasPrefix "${p}." q) paths) paths)
