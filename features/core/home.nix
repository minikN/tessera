{ lib, mkFeature, ... }:

let
  inherit (lib) mkIf mkMerge mkOption types;
in
mkFeature {
  name = "home";
  enableByDefault = true;

  doc = {
    summary = "Ties the user's login session to the apps other features provide.";
    description = ''
      Connects the system and the user's home-manager configuration. It is
      enabled by default and usually needs no configuration: it picks up
      whatever other features registered as the shell, window manager and
      editor.

      - **Login shell:** the shell in `globals.apps.shell` (set by e.g. the
        zsh feature) becomes the user's login shell and is added to the
        system's allowed shells.
      - **Editor:** `globals.apps.editor` (set by e.g. the Emacs feature) is
        exported as `$EDITOR`.
      - **home-manager command:** installed for home-only switches
        (`home-manager switch --flake .#<host>`).
    '';
    nixos = ''
      - `autostartWmOnTTY`: starts `globals.apps.wm` (if set) when logged in
        on the set tty.

        ```nix
        features = {
          sway.enable = true;
          home.autostartWmOnTTY = "/dev/tty1";
        };
        ```
    '';
    darwin = ''
      - **Applications:** apps from home-manager are copied to
        `~/Applications/Home Manager Apps`, so Spotlight and the Dock find
        them.
      - **Environment** `home.sessionVariables` is forwarded to `launchd` so
        that application started via Spotlight or Dock have the same environment
        as the terminal.
    '';
  };

  options = {
    autostartWmOnTTY = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "/dev/tty1";
      description = "TTY on which logging in starts the window manager in `globals.apps.wm` (NixOS only); `null` disables autostart.";
    };
  };

  nixos = { config, ... }:
    let
      shell = config.globals.apps.shell;
      wm = config.globals.apps.wm;
      tty = config.features.home.autostartWmOnTTY;
      user = config.features.user.username;
    in
    {
      environment.shells = mkIf (shell != null) [ shell ];
      users.users.${user}.shell = mkIf (shell != null) shell;

      environment.loginShellInit = mkIf (tty != null && wm != null) ''
        [[ $(tty) == ${tty} ]] && exec ${wm}
      '';
    };

  darwin = { config, ... }:
    let
      shell = config.globals.apps.shell;
      user = config.features.user.username;
    in
    {
      system.primaryUser = user;

      environment.shells = mkIf (shell != null) [ shell ];
      users.users.${user}.shell = mkIf (shell != null) shell;

      ## chsh as root every activation — nix can't change macOS login shells.
      launchd.daemons.defaultShell = {
        path = [ "/bin" "/usr/bin" "/usr/local/bin" ];
        serviceConfig.RunAtLoad = true;
        serviceConfig.UserName = "root";
        script = ''
          chsh -s ${if shell != null then shell else "/bin/zsh"} ${user}
        '';
      };
    };

  home = { config, pkgs, ... }: mkMerge [
    {
      programs.home-manager.enable = true;

      home.sessionVariables = lib.optionalAttrs (config.globals.apps.editor != null) {
        EDITOR = config.globals.apps.editor;
      };
    }
    (mkIf (config.globals.platform == "darwin") {
      targets.darwin = {
        copyApps.enable = true;
        linkApps.enable = false;
      };

      ## Push the user's PATH + sessionVariables into launchd so Dock-
      ## launched GUI apps see the same env as a login shell.
      launchd.agents.session-environment = {
        enable = true;
        config = {
          Label = "home-manager.session-environment";
          RunAtLoad = true;
          ProgramArguments =
            let
              script = pkgs.writeShellScript "session-environment" ''
                export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
                [ -r /etc/profile ]    && . /etc/profile
                [ -r "$HOME/.profile" ] && . "$HOME/.profile"
                launchctl setenv PATH "$PATH"

                ${lib.concatStringsSep "\n" (
                  lib.mapAttrsToList
                    (n: v: "launchctl setenv ${n} \"${v}\"")
                    config.home.sessionVariables
                )}
              '';
            in
            [ "${script}" ];
        };
      };
    })
  ];
}
