{ lib, evalOptions }:

## Check that each feature has `doc`, `summary` and `description`
## and every option has a description.
{
  pkgs,
  features,
}:

let
  nameOf = f: lib.concatStringsSep "." (lib.toList f.name);

  isMissingOrEmpty = text: !(builtins.isString text) || lib.trim text == "";

  docProblems = lib.concatMap (
    f:
    if f.doc == null then
      [ "${nameOf f}: no doc block" ]
    else
      lib.optional (isMissingOrEmpty (f.doc.summary or null)) "${nameOf f}: no doc.summary"
      ++ lib.optional (isMissingOrEmpty (f.doc.description or null)) "${nameOf f}: no doc.description"
  ) features;

  evaluatedOptions = evalOptions {
    inherit pkgs features;
    platform = if pkgs.stdenv.hostPlatform.isDarwin then "darwin" else "nixos";
  };
  options = builtins.filter (o: o.visible && !o.internal) (
    lib.optionAttrSetToDocList evaluatedOptions.options.features
  );
  optionProblems = map (o: "${o.name}: no description") (
    builtins.filter (o: isMissingOrEmpty o.description) options
  );

  allProblems = docProblems ++ optionProblems;
in
if allProblems == [ ] then
  pkgs.runCommandLocal "docs-check" { } "touch $out"
else
  throw "Missing documentation:\n${lib.concatMapStrings (p: "  - ${p}\n") allProblems}"
