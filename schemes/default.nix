## Built-in base16 schemes (plain hex), each with a light and a dark variant;
## `features.theme.polarity` picks the variant. `syntax` lists the syntax
## roles whose colour differs from the base16 styling guide.
##
## https://github.com/chriskempson/base16/blob/main/styling.md:
##
## - base00, base01, base02: BACKGROUND, CARET_ROW_COLOR, SELECTION_BACKGROUND
## - base03: DEFAULT_LINE_COMMENT
## - base04, base06: CONSOLE_GRAY_OUTPUT, LINE_NUMBER_ON_CARET_ROW_COLOR
## - base05, base07: TEXT, CONSOLE_WHITE_OUTPUT (both the text colour)
## - base08, base0A, base0B, base0C, base0E: the console's red, yellow, green,
##   cyan and magenta
## - base09: DEFAULT_PARAMETER, orange
## - base0D: the console's cyan too; Monokai has no blue (its console blue is
##   orange)
## - base0F: PHP_TAG, the embedded language tag colour
{
  default = {
    syntax = {
      variable = "base0C";
      constant = "base0D";
      number = "base05";
      type = "base0B";
      string = "base0D";
      builtin = "base0F";
      regexp = "base0B";
      function = "base0F";
      preprocessor = "base08";
    };
    light = {
      base00 = "ffffff";
      base01 = "f2f2f2";
      base02 = "c4c4c4";
      base03 = "595959";
      base04 = "595959";
      base05 = "000000";
      base06 = "193668";
      base07 = "000000";
      base08 = "a60000";
      base09 = "7a4f2f";
      base0A = "6f5500";
      base0B = "00663f";
      base0C = "005e8b";
      base0D = "3548cf";
      base0E = "531ab6";
      base0F = "721045";
    };
    dark = {
      base00 = "000000";
      base01 = "1e1e1e";
      base02 = "535353";
      base03 = "989898";
      base04 = "989898";
      base05 = "ffffff";
      base06 = "c6daff";
      base07 = "ffffff";
      base08 = "ff5f59";
      base09 = "dfaf7a";
      base0A = "d0bc00";
      base0B = "00c06f";
      base0C = "00d3d0";
      base0D = "79a8ff";
      base0E = "b6a0ff";
      base0F = "feacd0";
    };
  };
  monokai-pro = {
    syntax = {
      keyword = "base08";
      string = "base0A";
      function = "base0B";
      type = "base0C";
      constant = "base0E";
      number = "base0E";
      regexp = "base0E";
      variable = "base05";
      operator = "base08";
    };
    light = {
      base00 = "faf4f2";
      base01 = "f0eae9";
      base02 = "e1dbda";
      base03 = "a59fa0";
      base04 = "918c8e";
      base05 = "29242a";
      base06 = "706b6e";
      base07 = "29242a";
      base08 = "e14775";
      base09 = "e16032";
      base0A = "cc7a0a";
      base0B = "269d69";
      base0C = "1c8ca8";
      base0D = "1c8ca8";
      base0E = "7058be";
      base0F = "918c8e";
    };
    dark = {
      base00 = "2d2a2e";
      base01 = "373438";
      base02 = "464447";
      base03 = "727072";
      base04 = "939293";
      base05 = "fcfcfa";
      base06 = "c1c0c0";
      base07 = "fcfcfa";
      base08 = "ff6188";
      base09 = "fc9867";
      base0A = "ffd866";
      base0B = "a9dc76";
      base0C = "78dce8";
      base0D = "78dce8";
      base0E = "ab9df2";
      base0F = "939293";
    };
  };
}
