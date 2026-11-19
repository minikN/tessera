{ expect, ... }:

{
  with-bash = expect {
    platform = "nixos";
    features = {
      bash.enable = true;
      zsh.enable = true;
    };
    messages = [ "features.bash and features.zsh cannot both be enabled. Pick one." ];
  };
}
