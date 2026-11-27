# Tessera contributor guide

## Project shape

Tessera is a Nix flake library for composing NixOS, nix-darwin, and Home Manager configurations from independently optional **features**. It is not itself a collection of machine configurations: consumers supply hosts and globals to `lib.mkFlake`, and may add their own feature directory.

The public usage and option examples live in `README.md`. This file focuses on implementation structure and invariants. Keep both documents and feature `doc` blocks in sync with public behavior.

Primary implementation languages are Nix and Emacs Lisp embedded in Nix strings. Format Nix with the flake formatter (`nix fmt`, using `nixfmt-tree`). Mark Nix indented strings containing another language with a `# <lang>` comment immediately before the opening `''`, such as `config = # elisp` or `script = # bash`, so polymode selects the correct mode. This applies to new and edited inline code blocks, including embedded Emacs Lisp and shell code.

## Evaluation flow

1. `flake.nix` imports `lib/default.nix` with `nixpkgs.lib` and the flake inputs. It exports the library, overlay, documentation and package outputs, checks, and formatter for `x86_64-linux`, `aarch64-linux`, and `aarch64-darwin`.
2. `lib/default.nix` recursively discovers built-in features and constructs the package overlay. It also creates the public helpers, including `mkFeature`, `mkHost`, `mkFlake`, `mkDocs`, `mkElispConfig`, and `types`.
3. `lib/discover.nix` imports every `.nix` file below a feature or host directory. No central feature import list exists. Feature files receive `lib`, `mkFeature`, `mkElispConfig`, and `tessera` (`types`, `mkDocs`, and the discovered feature records).
4. `lib/mk-feature.nix` turns each feature declaration into a common options/globals module, optional platform modules, support checks, and documentation metadata.
5. `lib/mk-flake.nix` combines built-in and consumer features, merges inputs (consumer inputs win), discovers hosts, and calls `mkHost` for each one.
6. `lib/mk-host.nix` builds the system configuration and, unless `homeManager = false`, a standalone Home Manager configuration. Both system-embedded and standalone Home Manager use the same home modules. Home Manager requires `globals.user`; a system-only host without it defaults the user feature off. Explicitly enabling a home-only feature with `homeManager = false` is an assertion failure.

The resulting consumer outputs are `nixosConfigurations.<host>`, `darwinConfigurations.<host>`, and `homeConfigurations.<host>`. Host platform is inferred from `system` (`darwin` in the string selects nix-darwin). Host filenames, without `.nix`, become host names.

## Source map

- `lib/mk-feature.nix`: feature option names, automatic enablement, platform support, parent requirements, and module wrapping.
- `lib/mk-host.nix`: the central composition pipeline, globals, overlays, hardware profiles, host-specific modules, and embedded/standalone Home Manager.
- `lib/mk-flake.nix` and `lib/discover.nix`: consumer-facing composition and recursive discovery.
- `lib/globals-options.nix`: the shared vocabulary through which features cooperate.
- `lib/types.nix`: mergeable attrset-or-function keybinding options.
- `lib/mk-docs.nix`, `lib/eval-options.nix`, `lib/check-docs.nix`: generated HTML/Markdown, man and Info documentation, and documentation checks.
- `lib/mk-elisp-package.nix`, `lib/mk-elisp-config.nix`: generated Emacs packages and their integration into Home Manager's Emacs configuration.
- `features/`: built-in features, grouped by category only for organization.
- `packages/`: packages exposed through the overlay as `pkgs.tessera.<category>.<name>`.
- `schemes/`: base16 schemes; `lib/mk-scheme-attrs.nix` adds the `withHashtag` view.
- `tests/`: generated host checks, feature-specific checks, and Emacs ERT/byte-compilation checks.
- `.github/workflows/`: the authoritative per-platform CI check matrix and docs publication.

Useful canonical examples:

- `features/terminal/ghostty.nix`: a small feature with options, optional theme/font integration, and a global app contribution.
- `features/wm/sway.nix`: globals, keybinding functions, optional feature integration, and assertions.
- `features/editor/emacs.nix` and `features/editor/emacs/eglot.nix`: parent/nested features and generated Emacs configuration.
- `features/lang/javascript.nix`: a large cross-feature integration with editor-conditional behavior.
- `features/desktop/theme.nix`: rich options, read-only derived values, platform-specific behavior, and specialisations.

## Feature inspiration

When adding a feature, look for its counterpart in [Ordenada](https://github.com/minikN/ordenada) and [RDE](https://github.com/abcdw/rde), the projects acknowledged in `README.md`. Use their feature scope, options, integrations, and defaults as blueprints for what to implement where applicable. They are inspiration, not dogma: adapt their ideas to Tessera's architecture and current requirements rather than copying them uncritically.

## Feature contracts

A feature declaration has this shape:

```nix
{ lib, mkFeature, ... }:
mkFeature {
  name = "example"; # or [ "parent" "child" ]
  enableByDefault = false;
  platforms = null; # optional restriction, not an expansion of derived support
  doc = {
    summary = "Short summary";
    description = "User-facing behavior and examples.";
  };
  options = { config, pkgs, ... }: { };
  globals = { config, ... }: { };
  nixos = { config, pkgs, ... }: { };
  darwin = { config, pkgs, ... }: { };
  home = { config, pkgs, ... }: { };
}
```

All blocks except `name` are optional in practice, but documentation checks require `doc.summary`, `doc.description`, and a description on every visible option.

Important invariants:

- `name`, not the file path, determines `features.<name>`. Directory layout is organizational. Nested names create nested options and automatically require every ancestor feature to be enabled.
- `mkFeature` synthesizes `features.<name>.enable`; never redeclare it. New features are opt-in unless `enableByDefault = true` is intentional.
- Platform bodies are automatically wrapped in `mkIf features.<name>.enable`. Do not wrap the whole body in that same condition again. Conditional subsections still use `mkIf`, `mkMerge`, or `optionalAttrs` normally.
- Put feature options in the top-level `options` block, not in platform bodies. Platform bodies may return configuration and `imports`.
- `options` and `globals` are **not** automatically gated by the feature's enable flag. Gate global values with `lib.mkIf config.features.<name>.enable` where needed, especially before evaluating platform-specific packages.
- Platform support is derived from available blocks and package availability. A `home` block supports both system platforms. `platforms` can only narrow this. Explicitly enabling an unsupported feature is an assertion failure; an unsupported default-enabled feature is left alone.
- A home module must work in both embedded and standalone Home Manager. Do not use NixOS or nix-darwin options in it. Home modules are omitted with `homeManager = false`; explicitly enabling a feature that has only a home module in that case is an assertion failure.
- Host `features` may be an attrset or a module function when it needs `config`, `pkgs`, or other module arguments. Host-specific `nixos`, `darwin`, and `home` modules are appended after feature modules.

## Cross-feature design

Features cooperate through declared options and `config.globals`, not through a central wiring module.

`config.globals` contains:

- `user`: the complete static `globals` attrset passed to `mkFlake` (for example, `config.globals.user.user` and `.email`).
- `platform`: `"nixos"` or `"darwin"`.
- `wayland`, `autoloads`, and `wmControlledBar`: shared session state.
- `apps`: shell, terminal, editor, WM, launcher, bar, and password manager commands.

Providers contribute globals; consumers tolerate their absence. Guard optional integrations with `config.features.<other>.enable` or checks such as `apps.terminal != null`. Do not turn optional integrations into hard dependencies. Use Nix module priorities deliberately where alternative providers can set the same global.

Nested features are different: their parent is a hard requirement enforced by `mkFeature`. Generic parent options (for example, `features.emacs.earlyInit`) can serve as extension points for other features.

For keybindings that may be either attrsets or functions, use `tessera.types.keybindings` and apply the resulting function once with the documented parameters. See `features/wm/sway.nix` and `features/wm/aerospace.nix`.

Every keybinding shown by which-key, including all `C-c` commands and prefixes, must have a concise human-readable description. Use `("description" . command)` or a labelled prefix keymap when declaring a binding. To describe an existing binding without changing its command, use `tessera-keymaps-describe-key` from `emacs.keymaps`; call it only when that feature is enabled and defer the integration with `with-eval-after-load 'tessera-keymaps`. Bindings created dynamically must be described when they are created. The underlying keybindings must continue to work when `emacs.keymaps` is disabled.

## Packages, Emacs, and docs

`packages/<category>/<name>.nix` is discovered by `packagesFromDirectoryRecursive`. The overlay exposes it as `pkgs.tessera.<category>.<name>`; the flake also exposes it as `packages.<system>.<category>-<name>`. No separate package import list is needed.

Use `mkElispPackage` for standalone generated Emacs packages and `mkElispConfig` inside home modules to add packages, `require` forms, dependencies, and early-init code. Override generated packages with the active Emacs package set when composing them, as the language features do.

For packages we create, always prefix the package `name`/`pname` with `tessera-`; keep source filenames and overlay attributes unprefixed. For example, `packages/emacs/json-utils.nix` sets `name = "tessera-json-utils"` and is exposed as `pkgs.tessera.emacs.json-utils`. Third-party packages such as `combobulate.nix` retain their upstream names.

Emacs checks byte-compile with warnings as errors and run with a minimal `PATH`. External executables in generated Elisp must therefore use Nix store paths rather than relying on interactive shell lookup.

Documentation is generated from feature metadata and evaluated options. `mkDocs` produces Markdown and HTML, with `man` and `info` passthru outputs. Feature documentation belongs in the feature's `doc` block; broader usage changes belong in `README.md`.

## Tests and validation

`tests/hosts.nix` automatically evaluates, on both NixOS and macOS:

- a bare host;
- one host per supported feature, with that feature and its parents enabled;
- an all-features host that also enables opt-in boolean options;
- standalone Home Manager for the bare and all-features hosts.

These are evaluation checks, not full system builds. Failed assertions **and warnings** fail them. Consequently, a new feature must evaluate both alone and alongside every other supported feature. Only add to the `conflicting` list for a real, unavoidable feature conflict.

`tests/hosts.nix` also builds `emacs-all`, the Emacs of the all-features host on the current system. It starts that Emacs and fails if any of tessera's keys lacks a which-key description: every key under `C-c` followed by a letter in the global map and every loaded mode map, every key below those, and every key in a `tessera-*` prefix keymap. A new Emacs feature is therefore started alongside all others and has its descriptions checked without a feature test.

Feature-specific tests go in `tests/features/<category>/<feature>.nix`, mirroring the feature path. They are discovered automatically and use:

- `expect` for required assertion or warning messages;
- `check` for a cleanly evaluating host plus custom assertions about system and home configuration;
- `emacsCheck` for building the host's final Emacs package and running a behavioral Elisp `script` in batch Emacs, started as Emacs starts: the generated `early-init.el`, the packages, the generated configuration, then the startup hooks.

Use the `platform` argument passed to each feature test file for platform-neutral checks so they run on both Linux and macOS. Hard-code `platform = "nixos"` or `"darwin"` only for genuinely OS-specific checks. Discovery includes a check only when its declared platform matches the current flake system, so one OS never tries to realize the other's generated files. Prefer behavioral assertions over searching generated source for strings; package-selection assertions belong in `check`, while Emacs behavior belongs in `emacsCheck` or ERT.

### Writing tests

- Test behavior, not configuration. A check that a variable has the value the feature sets, or that a key is bound in the map the feature bound it in, restates the code and passes even when the behavior is broken. Drive the feature as a user would instead: open a buffer in the mode, press keys with `execute-kbd-macro`, and assert the resulting text, point, state or windows. Commands reading the minibuffer work this way too, in batch Emacs.
- Where batch Emacs cannot show the effect (display, echo area, screen lines), check what a key runs with `key-binding` in a buffer with the relevant modes and state active, so shadowing by other keymaps is caught. Check a setting directly only as a last resort, with a comment saying why.
- Exercise deferred configuration: load the library or open a buffer in the mode, so `with-eval-after-load` bodies and mode hooks run. Upstream packages (e.g. Evil Collection) often change settings only when a mode loads.
- Test what can break: conditional logic, both sides of optional integrations (with and without the other feature), interactions between features, and fixed bugs as regression checks. Do not test a single unconditional setting or the behavior of upstream packages themselves.
- Keep a check to one feature, in the test file of the feature implementing the behavior, and name it after that behavior. Do not repeat what `emacs-all` checks.
- Use the cheapest check that can observe the behavior. `expect` and `check` only evaluate; every distinct feature set in an `emacsCheck` builds its own Emacs, so put a feature's behavioral checks that need the same features into one script.
- Prefer public APIs to private (`--`) functions of upstream packages and to nixpkgs internals.
- Make sure a new check fails without the change it tests.

Emacs package tests have two parts: an ERT file `tests/packages/emacs/<name>.el` and explicit registration in `tests/packages/emacs/default.nix`, which also byte-compiles the package. Unlike feature tests, ERT registration is not automatic.

For focused validation, list check names and build only relevant ones:

```sh
nix eval --json .#checks.x86_64-linux --apply builtins.attrNames
nix build --no-link .#checks.x86_64-linux.formatting
nix build --no-link .#checks.x86_64-linux.docs
nix build --no-link .#checks.x86_64-linux.host-nixos-sway
nix build --no-link .#checks.x86_64-linux.sway-wiring
nix build --no-link .#checks.x86_64-linux.ert-json-utils
```

Nested dots in generated host check names become hyphens (for example, `host-nixos-emacs-eglot`). Substitute `aarch64-darwin` and `host-darwin-*` for macOS coverage. Documentation output can be built with `nix build --no-link .#docs`.

Run `nix fmt` after Nix edits and `nix flake check --no-build` for broad evaluation coverage. The full `nix flake check` is memory-intensive because it evaluates all hosts in one process; CI instead builds checks separately and filters out host checks for the other OS. Follow `.github/workflows/test.yml` when reproducing the full matrix.

## Change checklist

- Preserve automatic discovery; do not add central imports for ordinary features or packages.
- Preserve soft cross-feature integration and both Home Manager execution paths.
- Add or update feature docs and tests with behavior changes.
- Test platform support, assertions, warnings, and interactions affected by the change, not just Nix syntax.
- Update this file when architectural rules, directory conventions, or validation workflows change.
- Check `git status` after builds and remove only generated artifacts created by your own commands; use `--no-link` where practical to avoid replacing `result`.
