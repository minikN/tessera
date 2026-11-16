# tessera

[![docs](https://github.com/minikN/tessera/actions/workflows/docs.yml/badge.svg)](https://github.com/minikN/tessera/actions/workflows/docs.yml)
[![License](https://img.shields.io/github/license/minikN/tessera)](https://github.com/minikN/tessera/blob/main/LICENSE)

Composable features for NixOS, nix-darwin, and home-manager. A host picks
the features it wants and sets their options; features talk to each other
through shared globals. Hosts and features are discovered from folders:
drop a `.nix` file in the right place and it is picked up.

## Using tessera

Your configuration is a flake with tessera as an input. `mkFlake` builds
every host in `hosts/` from tessera's features plus your own:

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    tessera = {
      url = "github:minikN/tessera";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs: inputs.tessera.lib.mkFlake {
    inherit inputs;
    globals = {
      user = "jane";
      fullName = "Jane Doe";
      email = "jane@example.com";
      stateVersion = "26.05";
    };
    hosts = ./hosts;
    features = ./features;   # optional: your own features
  };
}
```

```
flake.nix
hosts/           # one file per machine
features/        # your own features, next to tessera's
```
## Documentation

tessera features multiple ways of consuming its configuration. The easiest
way would be to use the [online documentation](https://minikn.github.io/tessera/).

If desired there are ways to build the docs by yourself and view them offline:

```bash
nix build github:minikN/tessera#docs
open result/html/index.html   # the website (xdg-open on Linux)
ls result/markdown            # the Markdown it is built from
```

If man pages are preferred, the `manual` feature is on by default which
installs `tessera(5)` man pages. This feature is on by default. So even
a host with no features enabled manually, the man pages will be installed:

```nix
# hosts/laptop.nix
{
  system = "aarch64-darwin";
}
```

Switching to that configuration installs the man page:

```bash
sudo darwin-rebuild switch --flake .#laptop   # or nixos-rebuild, or home-manager switch
man tessera
```

With the `emacs` feature enabled, the `manual` feature also adds the
documentation to Emacs as an Info manual: `C-h i m Tessera`.

## How it works

`mkFlake` does three things:

1. Loads your `globals` (static constants).
2. Recursively imports every `.nix` file under tessera's `features/` and
   your `features` folder via `mkFeature`, producing a list of feature
   records.
3. Walks `hosts` and builds, for each host file:
   - `nixosConfigurations.<host>` *or* `darwinConfigurations.<host>` —
     dispatched on `system` (anything containing `darwin` → nix-darwin, else
     NixOS).
   - `homeConfigurations.<host>` — a standalone `homeManagerConfiguration`
     built from the *same* home modules that the system config embeds.

So every host gets both an embedded path (`{nixos,darwin}-rebuild switch`,
system + home together) and a standalone path (`home-manager switch`, home
only) for free.

Modules receive `inputs` (tessera's inputs merged with yours, yours win)
and `globals` as special arguments.

## Hosts

A host file is a plain attrset. The filename (without `.nix`) is the host
name. The only required key is `system`; the platform is inferred from it.

```nix
# hosts/slimboy.nix
{
  system = "x86_64-linux";
  hardware = [ "lenovo-thinkpad-t460" ];

  features = {
    zsh = {
      enable = true;
      extraConfig = ''
        export PATH="$HOME/.local/bin:$PATH"
      '';
    };
  };

  nixos = { pkgs, ... }: {
    networking.hostName = "slimboy";
    boot.kernelModules = [ "kvm-intel" ];
    boot.kernelPackages = pkgs.linuxPackagesFor pkgs.linux_latest;
  };

  home = { ... };   # optional — host-specific home-manager config
}
```

`features` may also be a module function when an option needs `config` — e.g.
wiring an agenix secret path into a feature:

```nix
# hosts/slimboy.nix
# ...
features = { config, ... }: {
  nas = {
    enable = true;
    credentialsFile = config.age.secrets.smb-credentials.path;
  };
};
# ...
```

| Key        | Required | Purpose                                                   |
| ---------- | -------- | --------------------------------------------------------- |
| `system`   | yes      | `x86_64-linux`, `aarch64-darwin`, etc.                    |
| `hardware` | no       | [nixos-hardware](https://github.com/NixOS/nixos-hardware) profiles to import, e.g. `[ "common-cpu-intel" "common-pc-ssd" ]`. NixOS only. |
| `features` | no       | Toggle features and set their options. Attrset, or a `{ config, ... }:` function for config-derived values (e.g. secret paths). |
| `nixos`    | no       | Host-specific NixOS config. Ignored on darwin hosts.      |
| `darwin`   | no       | Host-specific nix-darwin config. Ignored on NixOS hosts.  |
| `home`     | no       | Host-specific home-manager config.                        |

List the available hardware profiles with:

```bash
nix eval github:minikN/tessera#lib.hardwareProfiles
```

## Features

A feature is built with the `mkFeature` helper. It can declare three
platform blocks (`nixos`, `darwin`, `home`) plus shared options and a
contribution to the global namespace. Every block is independently optional.
Your own features look exactly like tessera's.

Put a feature anywhere in the folder you pass as `features` to `mkFlake`;
there is nothing to import, it is picked up automatically:

```nix
# features/shell/fish.nix
{ lib, mkFeature, ... }:

mkFeature {
  name = "fish";             # string or list of strings (nested: ["foo" "bar"])
  enableByDefault = false;   # if true, the feature is on unless a host disables it
  platforms = null;          # optional subset of [ "home" "nixos" "darwin" ] (see below)

  # Options live under features.fish.*
  # An `enable` option is always synthesized — don't redeclare it.
  options = { pkgs, ... }: {
    package = lib.mkPackageOption pkgs "fish" { };
  };

  # Optional. Contributions to config.globals.*
  globals = { config, ... }: {
    apps.shell = lib.mkIf config.features.fish.enable
      "${config.features.fish.package}/bin/fish";
  };

  nixos  = { ... }: { programs.fish.enable = true; };  # only goes into NixOS hosts
  darwin = { ... }: { programs.fish.enable = true; };  # only goes into darwin hosts
  home   = { config, ... }: {                          # goes into the user's home-manager config
    programs.fish.enable = true;
    programs.fish.package = config.features.fish.package;
  };
}
```

Enable it on any host with `features.fish.enable = true;`.

Each block's body is automatically wrapped in
`mkIf config.features.<name>.enable`, so you don't gate it yourself. The
`home` block runs in *both* the embedded home-manager (inside the system
config) and the standalone `homeConfigurations.<host>` output — keep it
free of system-level options.

**Platforms.** A feature supports Home, NixOS and macOS where it has a
block (a `home` block counts for both systems) and its `package` option,
if any, is available there. `platforms` only narrows that, for what can't
be derived (e.g. `gtk` installs Linux-only tools). Explicitly enabling a
feature on a host it doesn't support is an error; features that are only
on by default are left alone.

**Dependencies.** A nested feature (`emacs.keymaps`) requires its parent
(`emacs`); Enabling a feature without its requirements is an error.

### Keybindings

Every feature for an application that takes keybindings (window managers,
launchers, terminals, shells) has a `keybindings` option. Your bindings
are merged over the feature's defaults: new keys are added, and a key the
feature already binds is overridden.

If the feature has options that keybindings depend on (sway's `modifier`,
`left`, `right`, `up`, `down`), `keybindings` may also be a function of
them, plus `apps` (the global apps: terminal, launcher, …):

```nix
features.sway.keybindings = { modifier, left, apps, ... }: {
  "${modifier}+Shift+${left}" = "move left 50px";
  "${modifier}+t" = "exec ${apps.terminal}";
};
```

A plain attrset works too, and both forms can be mixed across modules.
Features without such options take a plain attrset, e.g.
`features.ghostty.keybindings."ctrl+shift+t" = "new_tab";`.

Feature authors get the type from the `tessera` argument and call the
function once with the parameters:

```nix
{ lib, mkFeature, tessera, ... }:
# ...
keybindings = lib.mkOption {
  type = tessera.types.keybindings lib.types.str;
  default = { };
  apply = f: f { inherit (cfg) modifier left right up down; inherit (config.globals) apps; };
};
```

## Globals

Two layers, both reachable as `config.globals.*`:

1. **User constants** — whatever is in your `globals`, copied verbatim into
   `config.globals.user`. So `config.globals.user.user`,
   `config.globals.user.email`, `config.globals.user.gpgKey`, etc.

2. **Framework/feature globals** — declared as options in
   `lib/globals-options.nix`:
   - `config.globals.platform` — `"nixos"` or `"darwin"`, auto-set per host.
   - `config.globals.apps.{shell,terminal,editor,wm,launcher}` — populated
     by features that contribute defaults.

Features read globals like any other config value:

```nix
nixos = { config, ... }: {
  environment.shells = lib.optional (config.globals.apps.shell != null)
    config.globals.apps.shell;
};
```

And contribute to them via the `globals` block of `mkFeature`:

```nix
globals = { config, ... }: {
  apps.shell = lib.mkIf config.features.zsh.enable
    "${config.features.zsh.package}/bin/zsh";
};
```

Leave it out with `features.manual.enable = false;`. To build only the man
page, run `nix build github:minikN/tessera#docs.man`.

In tessera, `nix flake check` fails when a feature has no `doc` block with a
`summary` and a `description`, or when an option has no description.

## Adding things

- **A new host** — drop a file in `hosts/`. Filename = host name.
- **A new feature** — drop a file in `features/<wherever>/<name>.nix` (in
  tessera or your own config). Folder structure is purely organizational;
  discovery is recursive.
- **Platform-specific behavior on an existing feature** — add or extend its
  `nixos = …`, `darwin = …`, or `home = …` block.

## Testing

Run these in your configuration:

```bash
# Evaluate every output (fast, catches type/eval errors)
nix flake check --no-build

# Build without activating
nix build .#darwinConfigurations.<host>.system
nix build .#nixosConfigurations.<host>.config.system.build.toplevel
nix build .#homeConfigurations.<host>.activationPackage
```

## License

GPLv3 — see [LICENSE](./LICENSE).

## Acknowledgements

tessera is heavily inspired / based on the idea of two other projects:
- [Andrew Tropin's RDE](https://github.com/abcdw/rde). The original idea of
  composable features / modules that can be picked and combined to match
  ones preferred environment. It's for Guix what tessera is for Nix. Many
  of tessera's features are inspired of RDE's (same options, similar
  implementation). The amount of work that's been done on RDE is truly
  impressive, and I'm thankful I can use it as inspiration for tessera.

- [Migal Moreno's Ordenada](https://github.com/migalmoreno/ordenada) (private). 
  The original project that took RDE's idea to Nix. It's discontinued and
  its repository is private, but I have [a fork](https://github.com/minikN/ordenada).
  tessera was born from the discontinuation of that project. I wanted to continue
  the ideas it brought under my own flag.

## AI
I was contributor to both [rde](https://github.com/abcdw/rde/commits/master/?author=minikN) and
[ordenada](https://github.com/minikN/ordenada/commits/master/?author=minikN) before I ever came
in touch with AI. But it's true: Nowadays, I simply don't have the time (family, job) anymore
to allocate as much of it to my projects as I'd like to and I use AI to make decent progress
in the time I have available. I am deliberate in my use of it. I use it in small chunks, one task
at a time. I review its code and mostly run multiple iterations until I'm happy. I never commit
something I don't fully understand.
