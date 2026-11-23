{ lib }:

pkgs: epkgs:
{
  name,
  config,
  summary ? "No description provided",
  packageRequires ? [ ],
}:
let
  elFile =
    pkgs.writeText "${name}.el" # elisp
      ''
        ;;; ${name}.el --- ${summary} -*- lexical-binding: t -*-

        ${config}
        (provide '${name})
      '';
in
epkgs.melpaBuild {
  pname = name;
  version = "0.1.0";
  src = elFile;
  inherit packageRequires;
  ignoreCompilationError = true;
}
