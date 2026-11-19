{
  lib,
  expect,
  check,
  ...
}:

{
  wiring = check {
    platform = "nixos";
    features = {
      sway.enable = true;
      ghostty.enable = true;
      rofi = {
        enable = true;
        enableLauncher = true;
        enablePasswordManager = true;
      };
      password-store.enable = true;
    };
    assertions =
      { home, ... }:
      let
        inherit (home.globals) apps;
        keys = home.wayland.windowManager.sway.config.keybindings;
        runs = key: app: (keys.${key} or null) == "exec ${toString app}";
      in
      [
        {
          assertion = lib.hasSuffix "/bin/sway" (toString apps.wm);
          message = "sway is the window manager";
        }
        {
          assertion = home.globals.wayland;
          message = "sway makes the session a Wayland one";
        }
        {
          assertion = runs "Mod4+d" apps.launcher;
          message = "Mod4+d runs the launcher";
        }
        {
          assertion = runs "Mod4+Return" apps.terminal;
          message = "Mod4+Return runs the terminal";
        }
        {
          assertion = runs "Mod4+p" apps.passwordManager;
          message = "Mod4+p runs the password manager";
        }
        {
          assertion =
            home.wayland.windowManager.sway.config.bars == [ ]
            && !home.globals.wmControlledBar
            && (keys."Mod4+b" or null) != "bar mode toggle";
          message = "without useGlobalBar, sway runs no bar";
        }
      ];
  };
  global-bar = check {
    platform = "nixos";
    features.sway = {
      enable = true;
      useGlobalBar = true;
    };
    home.globals.apps.bar = "bar";
    assertions =
      { home, ... }:
      let
        sway = home.wayland.windowManager.sway.config;
      in
      [
        {
          assertion = map (bar: bar.command) sway.bars == [ "bar" ];
          message = "useGlobalBar runs globals.apps.bar";
        }
        {
          assertion = (sway.keybindings."Mod4+b" or null) == "bar mode toggle";
          message = "Mod4+b shows or hides the bar";
        }
        {
          assertion = home.globals.wmControlledBar;
          message = "useGlobalBar tells bar features that sway runs the bar";
        }
      ];
  };
  global-bar-without-bar = expect {
    platform = "nixos";
    features.sway = {
      enable = true;
      useGlobalBar = true;
    };
    messages = [ "features.sway.useGlobalBar needs a bar in globals.apps.bar." ];
  };
}
