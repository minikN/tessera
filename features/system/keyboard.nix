{ lib, mkFeature, ... }:

let
  inherit (lib) mkOption types;
in
mkFeature {
  name = "keyboard";

  doc = {
    summary = "Keyboard layout for the console, X11 and Wayland.";
    description = ''
      `layout` sets the XKB layout, variant and options: by default a US layout
      with Caps Lock as an additional Control key (`ctrl:nocaps`). The layout
      is handed to home-manager, and window managers like sway use it for
      their own keyboard setup.

      ```nix
      features.keyboard = {
        enable = true;
        layout = { name = "de"; options = [ "ctrl:nocaps" ]; };
      };
      ```
    '';
    nixos = ''
      - **Console and X11:** the text console uses the (first) layout, display
        managers and X11 sessions use all of it.
    '';
    darwin = ''
      - **Caps Lock:** macOS keeps its own layout; only `ctrl:nocaps` is
        applied, remapping Caps Lock to Control.
    '';
  };

  options = {
    layout = mkOption {
      description = "Keyboard layout.";
      default = {
        name = "us";
        options = [ "ctrl:nocaps" ];
      };
      type = types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            default = "us";
            description = "XKB layout (comma-separated for multi-layout; tty uses first).";
          };
          variant = mkOption {
            type = types.str;
            default = "";
            description = "XKB variant (e.g. dvorak, nodeadkeys).";
          };
          options = mkOption {
            type = types.listOf types.str;
            default = [ ];
            description = "XKB options (e.g. ctrl:nocaps).";
          };
        };
      };
    };
  };

  nixos =
    { config, ... }:
    let
      cfg = config.features.keyboard.layout;
    in
    {
      console.keyMap = builtins.elemAt (lib.splitString "," cfg.name) 0;

      ## Read by display managers + X11; Wayland compositors set their own.
      services.xserver.xkb = {
        inherit (cfg) variant;
        layout = cfg.name;
        options = lib.concatStringsSep "," cfg.options;
      };
    };

  darwin =
    { config, ... }:
    let
      cfg = config.features.keyboard.layout;
    in
    {
      system.keyboard.enableKeyMapping = true;
      system.keyboard.remapCapsLockToControl = builtins.elem "ctrl:nocaps" cfg.options;
    };

  home =
    { config, ... }:
    let
      cfg = config.features.keyboard.layout;
    in
    {
      home.keyboard = {
        layout = cfg.name;
        inherit (cfg) options variant;
      };
    };
}
