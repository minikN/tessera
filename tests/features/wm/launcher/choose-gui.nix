{ lib, check, ... }:

{
  roles = check {
    platform = "darwin";
    features = {
      choose-gui = {
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
          assertion = lib.hasSuffix "-choose-launcher" (toString home.globals.apps.launcher);
          message = "enableLauncher makes choose the launcher";
        }
        {
          assertion = lib.hasSuffix "/bin/choose-pass" (toString home.globals.apps.passwordManager);
          message = "enablePasswordManager makes choose-pass the password manager";
        }
        {
          assertion = lib.getName home.services.gpg-agent.pinentry.package == "pinentry-choose";
          message = "enablePinentry makes pinentry-choose gnupg's pinentry";
        }
      ];
  };
}
