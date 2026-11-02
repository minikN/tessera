{ lib, mkFeature, ... }:

mkFeature {
  name = "ls";

  doc = {
    summary = "A colourful `ls` that lists directories first";
    description = ''
      Makes `ls` an alias for `ls --color=auto --group-directories-first`. The
      bash and zsh features enable it automatically.
    '';
    darwin = ''
      - **GNU ls:** uses `gls` from GNU coreutils, since the `ls` that ships
        with macOS doesn't support these flags
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
      isDarwin = config.globals.platform == "darwin";
      binary = if isDarwin then "gls" else "ls";
    in
    {
      home.packages = lib.optional isDarwin pkgs.coreutils-prefixed;
      home.shellAliases.ls = "${binary} --color=auto --group-directories-first";
    };
}
