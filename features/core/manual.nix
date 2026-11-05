{ mkFeature, tessera, ... }:

mkFeature {
  name = "manual";
  enableByDefault = true;

  doc = {
    summary = "Tessera's documentation as a man page";
    description = ''
      Installs the tessera documentation as the `tessera(5)` man page,
      so `man tessera` shows it in the terminal. It is enabled by default.
    '';
  };

  home =
    { pkgs, ... }:
    {
      home.packages = [
        (tessera.mkDocs {
          inherit pkgs;
          inherit (tessera) features;
        }).man
      ];
    };
}
