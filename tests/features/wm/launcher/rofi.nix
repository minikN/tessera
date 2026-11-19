{ lib, check, ... }:

{
  roles = check {
    platform = "nixos";
    features = {
      rofi = {
        enable = true;
        enableLauncher = true;
        enablePasswordManager = true;
        enablePinentry = true;
      };
      password-store.enable = true;
      gnupg.enable = true;
    };
    assertions =
      { home, ... }:
      [
        {
          assertion = lib.hasSuffix "/bin/rofi -show drun" (toString home.globals.apps.launcher);
          message = "enableLauncher makes rofi the launcher";
        }
        {
          assertion = lib.hasSuffix "/bin/rofi-pass" (toString home.globals.apps.passwordManager);
          message = "enablePasswordManager makes rofi-pass the password manager outside Wayland";
        }
        {
          assertion = lib.getName home.services.gpg-agent.pinentry.package == "pinentry-rofi";
          message = "enablePinentry makes pinentry-rofi gnupg's pinentry";
        }
      ];
  };
  password-manager-on-wayland = check {
    platform = "nixos";
    features = {
      rofi = {
        enable = true;
        enablePasswordManager = true;
      };
      password-store.enable = true;
    };
    home.globals.wayland = true;
    assertions =
      { home, ... }:
      [
        {
          assertion = lib.hasSuffix "/bin/tessen" (toString home.globals.apps.passwordManager);
          message = "on Wayland, enablePasswordManager makes tessen the password manager";
        }
      ];
  };
}
