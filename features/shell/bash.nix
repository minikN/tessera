{ lib, mkFeature, ... }:

mkFeature {
  name = "bash";

  doc = {
    summary = "Bash as the login shell.";
    description = ''
      Installs interactive Bash with completion and registers it as
      `globals.apps.shell`.

      - **Files:** history goes to `~/.local/state/bash/history`;
        `extraConfig` is appended to `.bash_profile`.
      - **Keys:** `keybindings` are readline bindings, written to `~/.inputrc`.

      It cannot be enabled together with other shell feature.
    '';
  };

  options = { pkgs, ... }: {
    package = lib.mkPackageOption pkgs "bash" { default = [ "bashInteractive" ]; };
    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Extra lines appended to .bash_profile.";
    };
    keybindings = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = { "\\e[A" = "history-search-backward"; };
      description = "Readline keybindings (key sequence = function), written to ~/.inputrc.";
    };
  };

  globals = { config, ... }: {
    apps.shell = lib.mkIf
      (config.features.bash.enable && !config.features.zsh.enable)
      "${config.features.bash.package}/bin/bash";
  };

  home = { config, lib, pkgs, ... }: {
    assertions = [{
      assertion = !(config.features.bash.enable && config.features.zsh.enable);
      message = "features.bash and features.zsh cannot both be enabled. Pick one.";
    }];

    features.ls.enable = lib.mkDefault true;

    home.packages = [
      config.features.bash.package
      pkgs.bash-completion
    ];

    programs.bash = {
      enable = true;
      historyFile = "${config.xdg.stateHome}/bash/history";
      profileExtra = config.features.bash.extraConfig;
      bashrcExtra = ''
        [[ $- == *i* && -r ${pkgs.bash-completion}/etc/profile.d/bash_completion.sh ]] && \
          source ${pkgs.bash-completion}/etc/profile.d/bash_completion.sh
      '';
    };

    programs.readline = lib.mkIf (config.features.bash.keybindings != { }) {
      enable = true;
      bindings = config.features.bash.keybindings;
    };

    home.activation.createBashHistoryDir =
      lib.hm.dag.entryAfter [ "writeBoundary" ]
        "run mkdir -p ${lib.escapeShellArg "${config.xdg.stateHome}/bash"}";
  };
}
