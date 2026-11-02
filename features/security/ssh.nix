{ lib, mkFeature, ... }:

let
  inherit (lib)
    mkDefault
    mkEnableOption
    mkIf
    mkOption
    types
    ;
in
mkFeature {
  name = "ssh";

  doc = {
    summary = "SSH client settings and, on NixOS, an SSH server.";
    description = ''
      Configures the SSH client. `matchBlocks` holds per-host settings. An
      ssh-agent is started unless gpg-agent already serves SSH keys (see
      gnupg feature).

      **Caution: Turning off the `user` feature will drop the `authorizedKeys`
      file. Make sure you don't get locked out of a remote machine.**

      ```nix
      features.ssh = {
        enable = true;
        matchBlocks.server = { hostname = "10.0.0.10"; user = "jane"; };
      };
      ```
    '';
    nixos = ''
      - **Server:** `daemon.enable` runs sshd and opens its port. Password and
        root logins are off by default (`daemon.passwordAuthentication`,
        `daemon.permitRootLogin`); `authorizedKeyFiles` lists the public keys
        that may log in as the user.

        ```nix
        features.ssh = {
          enable = true;
          daemon.enable = true;
          authorizedKeyFiles = [ ../keys/me.pub ];
        };
        ```
    '';
  };

  options = _: {
    daemon = {
      enable = mkEnableOption "the SSH server daemon (sshd)";
      passwordAuthentication = mkOption {
        type = types.bool;
        default = false;
        description = "Allow password (and keyboard-interactive) authentication.";
      };
      permitRootLogin = mkOption {
        type = types.enum [
          "yes"
          "no"
          "prohibit-password"
          "without-password"
          "forced-commands-only"
        ];
        default = "no";
        description = "Value for sshd's PermitRootLogin.";
      };
    };

    authorizedKeyFiles = mkOption {
      type = types.listOf types.path;
      default = [ ];
      description = "Public key files authorized for the user.";
    };

    matchBlocks = mkOption {
      type = types.attrs;
      default = { };
      description = "SSH client match-block stanzas.";
    };
  };

  home = { config, ... }: {
    services.ssh-agent.enable = mkDefault (!(config.services.gpg-agent.enableSshSupport or false));

    programs.ssh = {
      enable = true;
      enableDefaultConfig = false;
      matchBlocks = config.features.ssh.matchBlocks;
    };
  };

  nixos =
    { config, ... }:
    mkIf config.features.ssh.daemon.enable {
      services.openssh = {
        enable = true;
        openFirewall = true;
        settings = {
          PasswordAuthentication = config.features.ssh.daemon.passwordAuthentication;
          KbdInteractiveAuthentication = config.features.ssh.daemon.passwordAuthentication;
          PermitRootLogin = config.features.ssh.daemon.permitRootLogin;
        };
      };

      users.users = mkIf config.features.user.enable {
        ${config.features.user.username}.openssh.authorizedKeys.keyFiles =
          config.features.ssh.authorizedKeyFiles;
      };
    };
}
