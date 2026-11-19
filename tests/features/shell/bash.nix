{ lib, check, ... }:

{
  defaults = check {
    platform = "nixos";
    features.bash.enable = true;
    assertions =
      { home, ... }:
      [
        {
          assertion = lib.hasSuffix "/bin/bash" (toString home.globals.apps.shell);
          message = "bash is the shell";
        }
        {
          assertion = home.features.ls.enable;
          message = "bash enables ls";
        }
        {
          assertion = home.programs.bash.historyFile == "${home.xdg.stateHome}/bash/history";
          message = "bash keeps its history in the XDG state directory";
        }
      ];
  };
}
