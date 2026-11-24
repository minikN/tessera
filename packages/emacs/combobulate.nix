{
  lib,
  pkgs,
  emacsPackages,
}:

emacsPackages.trivialBuild rec {
  pname = "combobulate";
  version = "1.0.0-unstable-2026-09-21";

  src = pkgs.fetchFromGitHub {
    owner = "mickeynp";
    repo = "combobulate";
    rev = "f7ea37b7ed5a463781a4b7122e4563f1c0fdc90f";
    hash = "sha256-xlxFZ3gWi+sJ4AgNDB1d7u9bp0HAjOMj6q3XVO6rtOE=";
  };

  packageRequires = [ emacsPackages.transient ];

  meta = {
    description = "Structured editing and navigation with tree-sitter";
    homepage = "https://github.com/mickeynp/combobulate";
    license = lib.licenses.gpl3Plus;
  };
}
