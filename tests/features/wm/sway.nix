{ expect, ... }:

{
  global-bar-without-bar = expect {
    platform = "nixos";
    features.sway = {
      enable = true;
      useGlobalBar = true;
    };
    messages = [ "features.sway.useGlobalBar needs a bar in globals.apps.bar." ];
  };
}
