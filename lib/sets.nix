{ lib }:

## Parses a module and collects all the `globals` it sets.
args: feature:
let
  block = if builtins.isFunction feature.globals then feature.globals args else feature.globals;

  isSet =
    v:
    let
      r = builtins.tryEval (builtins.isAttrs v);
    in
    r.success && r.value;

  walk =
    path: v:
    if !isSet v || lib.isDerivation v then
      [ path ]
    else if v ? _type then
      if
        builtins.elem v._type [
          "if"
          "override"
          "order"
        ]
      then
        walk path v.content
      else if v._type == "merge" then
        lib.concatMap (walk path) v.contents
      else
        [ path ]
    else
      lib.concatLists (lib.mapAttrsToList (n: walk (path ++ [ n ])) v);
in
if feature.globals == null then
  [ ]
else
  lib.sort lib.lessThan (map (p: lib.concatStringsSep "." ([ "globals" ] ++ p)) (walk [ ] block))
