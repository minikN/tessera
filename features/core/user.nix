{ lib, mkFeature, ... }:

let
  inherit (lib) mkOption types;
in
mkFeature {
  name = "user";
  enableByDefault = true;

  doc = {
    summary = "The user account the configuration is for.";
    description = ''
      Describes the user the configuration is for. It is enabled by default:
      `username`, `fullName` and `email` come from your globals
      (`globals.nix`), and `homeDirectory` follows the platform. Other
      features use these values, e.g. the Emacs feature sets the user's name
      and mail address from them.

      - **home-manager:** `username` and `homeDirectory` are also handed to
        home-manager.

      ```nix
      # globals.nix
      {
        user = "jane";
        fullName = "Jane Doe";
        email = "jane@example.com";
        stateVersion = "26.05";
      }
      ```
    '';
    nixos = ''
      - **Account:** creates a normal user with `fullName` as its description
        and `extraGroups` (by default `wheel`, which allows `sudo`).
    '';
    darwin = ''
      - **Account:** describes the existing macOS user (home directory and full
        name); the account itself is created by macOS, not by Nix.
    '';
  };

  options = { config, ... }: {
    username = mkOption {
      type = types.str;
      defaultText = lib.literalExpression "config.globals.user.user";
      default = config.globals.user.user or "user";
      description = "Username.";
    };
    fullName = mkOption {
      type = types.str;
      defaultText = lib.literalExpression "config.globals.user.fullName";
      default = config.globals.user.fullName or "";
      description = "Full name.";
    };
    email = mkOption {
      type = types.str;
      defaultText = lib.literalExpression "config.globals.user.email";
      default = config.globals.user.email or "";
      description = "Email address.";
    };
    homeDirectory = mkOption {
      type = types.str;
      defaultText = lib.literalMD "`/Users/<username>` on macOS, `/home/<username>` on Linux";
      default =
        if config.globals.platform == "darwin" then
          "/Users/${config.features.user.username}"
        else
          "/home/${config.features.user.username}";
      description = "Home directory.";
    };
    extraGroups = mkOption {
      type = types.listOf types.str;
      default = [ "wheel" ];
      description = "Extra NixOS groups.";
    };
  };

  nixos = { config, ... }: {
    users.users.${config.features.user.username} = {
      isNormalUser = true;
      home = config.features.user.homeDirectory;
      description = config.features.user.fullName;
      extraGroups = config.features.user.extraGroups;
    };
  };

  darwin = { config, ... }: {
    users.users.${config.features.user.username} = {
      home = config.features.user.homeDirectory;
      description = config.features.user.fullName;
    };
  };

  home = { config, ... }: {
    home.username = lib.mkDefault config.features.user.username;
    home.homeDirectory = lib.mkDefault config.features.user.homeDirectory;
  };
}
