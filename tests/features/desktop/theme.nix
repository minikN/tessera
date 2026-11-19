{
  lib,
  expect,
  check,
  ...
}:

let
  ## A scheme with only a light variant
  scheme.light = lib.genAttrs (map (i: "base0${lib.toHexString i}") (lib.range 0 15)) (_: "ffffff");
in
{
  missing-polarity = expect {
    platform = "darwin";
    features.theme = {
      enable = true;
      inherit scheme;
      polarity = "dark";
    };
    messages = [ ''features.theme.scheme has no "dark" variant, which polarity = "dark" needs.'' ];
  };
  toggle-without-other-polarity = expect {
    platform = "nixos";
    features.theme = {
      enable = true;
      inherit scheme;
      enableToggle = true;
    };
    messages = [ ''features.theme.scheme has no "dark" variant, which enableToggle needs.'' ];
  };
  toggle = check {
    platform = "nixos";
    features.theme = {
      enable = true;
      enableToggle = true;
    };
    assertions =
      { config, home, ... }:
      let
        dark = config.specialisation.dark.configuration;
        darkHome = dark.home-manager.users.${home.home.username};
        ## Whether each command toggle-theme runs with sudo may run without a
        ## password
        sudoAllowed =
          config: home:
          let
            script =
              (lib.findFirst (p: lib.getName p == "toggle-theme") { text = ""; } home.home.packages).text;
            commands = map (lib.removePrefix "sudo ") (
              builtins.filter (lib.hasPrefix "sudo ") (map lib.trim (lib.splitString "\n" script))
            );
            allowed = lib.concatMap (
              rule:
              map (c: c.command) (
                builtins.filter (c: builtins.isAttrs c && builtins.elem "NOPASSWD" c.options) rule.commands
              )
            ) config.security.sudo.extraRules;
          in
          commands != [ ] && lib.all (c: builtins.elem c allowed) commands;
      in
      [
        {
          assertion = dark.features.theme.polarity == "dark" && darkHome.features.theme.polarity == "dark";
          message = "the specialisation flips the polarity for the system and home-manager";
        }
        {
          assertion = darkHome.features.theme.colors.base00 == darkHome.features.theme.scheme.dark.base00;
          message = "the specialisation's colours come from the dark variant";
        }
        {
          assertion = sudoAllowed config home;
          message = "toggle-theme may run its sudo commands without a password";
        }
        {
          assertion = sudoAllowed dark darkHome;
          message = "in the specialisation, toggle-theme may run its sudo commands without a password";
        }
      ];
  };
}
