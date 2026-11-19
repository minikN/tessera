{ lib, check, ... }:

let
  baseDirs = {
    configHome = "/srv/config";
    dataHome = "/srv/data";
    cacheHome = "/srv/cache";
    stateHome = "/srv/state";
  };
in
{
  base-dirs = check {
    platform = "nixos";
    features.xdg = { inherit baseDirs; };
    assertions =
      { home, ... }:
      [
        {
          assertion = lib.all (dir: home.xdg.${dir} == baseDirs.${dir}) (lib.attrNames baseDirs);
          message = "baseDirs become home-manager's XDG base directories";
        }
      ];
  };
  user-dirs-nixos = check {
    platform = "nixos";
    features = { };
    assertions =
      { config, home, ... }:
      [
        {
          assertion =
            home.xdg.userDirs.enable && home.xdg.userDirs.documents == "${home.home.homeDirectory}/documents";
          message = "on NixOS, the user folders go to xdg-user-dirs, in lower case";
        }
        {
          assertion = !config.xdg.portal.wlr.enable && config.xdg.portal.config.common.default == "gtk";
          message = "without Wayland, only the GTK portal is used";
        }
      ];
  };
  user-dirs-darwin = check {
    platform = "darwin";
    features = { };
    assertions =
      { home, ... }:
      [
        {
          assertion =
            home.home.sessionVariables.XDG_DOCUMENTS_DIR or null == "${home.home.homeDirectory}/Documents";
          message = "on macOS, the user folders are capitalized XDG_*_DIR variables";
        }
      ];
  };
  portals-on-wayland = check {
    platform = "nixos";
    features = { };
    nixos.globals.wayland = true;
    assertions =
      { config, ... }:
      [
        {
          assertion = config.xdg.portal.wlr.enable && config.xdg.portal.config.common.default == "gtk;wlr";
          message = "on Wayland, the wlr portal is added";
        }
      ];
  };
}
