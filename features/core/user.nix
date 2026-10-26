{ lib, mkFeature, ... }:

let
  inherit (lib) mkOption types;
in
mkFeature {
  name = "user";
  enableByDefault = true;

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
        if config.globals.platform == "darwin"
        then "/Users/${config.features.user.username}"
        else "/home/${config.features.user.username}";
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
