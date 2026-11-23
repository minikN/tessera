{ mkFeature, tessera, ... }:

mkFeature {
  name = "manual";
  enableByDefault = true;

  doc = {
    summary = "Tessera's documentation as a man page and an Info manual";
    description = ''
      Installs the tessera documentation as the `tessera(5)` man page,
      so `man tessera` shows it in the terminal. It is enabled by default.

      - With the emacs feature, the same documentation is an Info manual:
        `C-h i` lists it under "Tessera", `C-h i m Tessera` opens it
    '';
  };

  home =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      docs = tessera.mkDocs {
        inherit pkgs;
        inherit (tessera) features;
      };
    in
    lib.mkMerge [
      { home.packages = [ docs.man ]; }
      (lib.mkIf config.features.emacs.enable {
        programs.emacs.extraConfig = # elisp
          ''
            (with-eval-after-load 'info
              (add-to-list 'Info-additional-directory-list "${docs.info}/share/info"))
          '';
      })
    ];
}
