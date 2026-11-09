{ lib, mkElispPackage }:

pkgs:
{
  name,
  config,
  elispPackages ? _: [ ],
  summary ? "No description provided",
  earlyInit ? "",
  addToInitEl ? true,
  manual ? null,
}:
{
  programs.emacs = {
    extraPackages =
      epkgs:
      let
        deps = elispPackages epkgs;
      in
      deps
      ++ [
        (mkElispPackage pkgs epkgs {
          inherit
            name
            config
            summary
            manual
            ;
          packageRequires = deps;
        })
      ];
    extraConfig = lib.optionalString addToInitEl "(require '${name})";
  };

  features.emacs.earlyInit = earlyInit;
}
