{ lib }:

## Evaluate the options of `features` with mocked user options
{ pkgs, features, platform ? "nixos" }:

lib.evalModules {
  modules = [
    ./globals-options.nix
    {
      _module.args.pkgs = pkgs;
      globals.platform = platform;
      globals.user = {
        user = "user";
        fullName = "User";
        email = "user@example.com";
        stateVersion = lib.trivial.release;
      };
    }
  ] ++ map (f: { _file = f.file or "<unknown>"; imports = [ f.commonModule ]; }) features;
}
