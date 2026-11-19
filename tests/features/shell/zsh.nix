{
  lib,
  expect,
  check,
  ...
}:

{
  defaults = check {
    platform = "darwin";
    features.zsh.enable = true;
    assertions =
      { home, ... }:
      [
        {
          assertion = lib.hasSuffix "/bin/zsh" (toString home.globals.apps.shell);
          message = "zsh is the shell";
        }
        {
          assertion = home.features.ls.enable;
          message = "zsh enables ls";
        }
        {
          assertion =
            home.programs.zsh.dotDir == "${home.xdg.configHome}/zsh"
            && home.programs.zsh.history.path == "${home.xdg.stateHome}/zsh/history";
          message = "zsh keeps its configuration and history in the XDG directories";
        }
      ];
  };
  keybindings = check {
    platform = "darwin";
    features.zsh = {
      enable = true;
      keybindings."^[[A" = "history-search-backward";
    };
    assertions =
      { home, ... }:
      [
        {
          assertion = lib.hasInfix "bindkey '^[[A' history-search-backward" home.programs.zsh.initContent;
          message = "keybindings become bindkey lines";
        }
      ];
  };
  with-bash = expect {
    platform = "nixos";
    features = {
      bash.enable = true;
      zsh.enable = true;
    };
    messages = [ "features.bash and features.zsh cannot both be enabled. Pick one." ];
  };
}
