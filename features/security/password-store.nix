{ lib, mkFeature, ... }:

mkFeature {
  name = "password-store";

  doc = {
    summary = "pass, the standard Unix password manager, with one-time codes.";
    description = ''
      Installs pass with the pass-otp extension (`pass otp` for one-time
      codes) and keeps the store in `storeDir`. Entries are encrypted with
      your GPG key (see the gnupg feature).

      - **Menus:** launcher features build password menus on top of it and
        register them as `globals.apps.passwordManager`: rofi on Linux,
        choose-gui on macOS.
    '';
  };

  options = { config, pkgs, ... }:
    let
      inherit (lib) mkOption types;
      passPkg =
        if config.globals.wayland && config.globals.platform == "nixos"
        then "pass-wayland"
        else "pass";
    in
    {
      package = mkOption {
        type = types.package;
        defaultText = lib.literalMD "`pkgs.pass` with the `pass-otp` extension (`pkgs.pass-wayland` on NixOS hosts running Wayland)";
        default = pkgs.${passPkg}.withExtensions (exts: [ exts.pass-otp ]);
        description = "The pass package to use (pass-wayland on Wayland/NixOS), with the pass-otp extension.";
      };

      storeDir = mkOption {
        type = types.str;
        defaultText = lib.literalExpression ''"''${config.features.xdg.baseDirs.stateHome}/password-store"'';
        default = "${config.features.xdg.baseDirs.stateHome}/password-store";
        description = "Password store location, exported as PASSWORD_STORE_DIR.";
      };
    };

  home = { config, ... }:
    let
      cfg = config.features.password-store;
    in
    {
      programs.password-store = {
        enable = true;
        package = cfg.package;
        settings.PASSWORD_STORE_DIR = cfg.storeDir;
      };
    };
}
