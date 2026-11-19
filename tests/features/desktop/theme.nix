{ lib, expect, ... }:

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
}
