{ lib }:

{
  ## An attrset, or a function of the feature's key-related options returning
  ## one. Attrsets are coerced to functions, so definitions of both forms merge.
  keybindings = valueType:
    lib.types.coercedTo (lib.types.attrsOf valueType) (attrs: _: attrs)
      (lib.types.functionTo (lib.types.attrsOf valueType));
}
