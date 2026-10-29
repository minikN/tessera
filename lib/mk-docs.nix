{
  lib,
  inputs,
  evalDocs,
  setsOf,
}:

## Build the documentation of the documented `features`: one Markdown page per
## feature, grouped by folder, and an mdBook site from them.
##
## The result has two folders:
##   $out/markdown  the generated Markdown (mdBook's source)
##   $out/html      the website built from it
##
## `intro` is the Markdown file shown as the book's first page.
{
  pkgs,
  features,
  title ? "tessera",
  intro ? ../README.md,
}:

let
  inherit (lib) concatStringsSep concatMapStringsSep optionalString;

  ## Some facts can only be found out by evaluating the features: which
  ## platforms they support, their options and what they set. So we evaluate
  ## all features twice, once as a Linux (NixOS) host and once as a macOS
  ## host.
  contexts = {
    nixos = evalDocs {
      pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
      inherit features;
      platform = "nixos";
    };
    darwin = evalDocs {
      pkgs = inputs.nixpkgs.legacyPackages.aarch64-darwin;
      inherit features;
      platform = "darwin";
    };
  };

  ## The arguments a module function gets (`config`, `options`, ...), taken
  ## from one of the evaluations above.
  argsOf = e: {
    inherit (e) config options;
    inherit lib;
    pkgs = e._module.args.pkgs;
  };

  ## Only features with a `doc` block get a page.
  documented = builtins.filter (f: f.doc != null) features;

  ## The feature's name as written in a host: "emacs.keymaps".
  nameOf = f: concatStringsSep "." (lib.toList f.name);

  ## Where the feature lives in the repository, e.g.
  ## "features/wm/launcher/rofi.nix". `f.file` is a path in the Nix store, so
  ## we cut off everything before "features/".
  sourceOf =
    f:
    builtins.unsafeDiscardStringContext (
      builtins.head (builtins.match ".*/(features/.*)" (toString f.file))
    );

  ## The folder below features/ is the feature's category ("wm/launcher").
  categoryOf = f: lib.removePrefix "features/" (dirOf (sourceOf f));

  ## How a category is shown in the table of contents: "Wm › Launcher".
  categoryTitle =
    c:
    concatMapStringsSep " › " (s: lib.toUpper (lib.substring 0 1 s) + lib.substring 1 (-1) s) (
      lib.splitString "/" c
    );

  ## Where the feature's page goes: "wm/launcher/rofi.md".
  pathOf = f: "${categoryOf f}/${nameOf f}.md";

  ## Which of the three platforms the feature works on. `supports` comes from
  ## mkFeature. A home-manager-only setup works on any OS, so "home" counts
  ## if either evaluation supports it.
  supported = f: {
    home = lib.any (e: f.supports "home" (argsOf e)) [
      contexts.nixos
      contexts.darwin
    ];
    nixos = f.supports "nixos" (argsOf contexts.nixos);
    darwin = f.supports "darwin" (argsOf contexts.darwin);
  };

  ## Every option below `features`, as a flat list. Each entry has the
  ## option's name, description, type, default and so on. Options hidden
  ## from users are left out.
  options = builtins.filter (o: o.visible && !o.internal) (
    lib.optionAttrSetToDocList contexts.nixos.options.features
  );

  ## Feature names as lists, e.g. [ "emacs" "keymaps" ].
  names = map (f: lib.toList f.name) features;

  ## The feature an option belongs to. Option names start with the feature
  ## name ("features.emacs.keymaps.keys.app"), but nested features make that
  ## ambiguous: both "emacs" and "emacs.keymaps" fit. The longest fitting
  ## name wins, so the option above belongs to "emacs.keymaps", not "emacs".
  ## (`o.loc` is the option name as a list; `drop 1` removes "features".)
  ownerOf =
    o:
    lib.foldl' (
      best: n:
      if
        lib.take (builtins.length n) (lib.drop 1 o.loc) == n && builtins.length n > builtins.length best
      then
        n
      else
        best
    ) [ ] names;

  ## The options of one feature, its `enable` option first.
  optionsOf =
    f:
    let
      own = builtins.filter (o: ownerOf o == lib.toList f.name) options;
      isEnable = o: o.loc == [ "features" ] ++ lib.toList f.name ++ [ "enable" ];
    in
    builtins.filter isEnable own ++ builtins.filter (o: !isEnable o) own;

  ## helpers
  code = text: if lib.hasInfix "\n" text then "\n\n```nix\n${text}\n```" else "`${text}`";
  value = v: if v._type == "literalMD" then v.text else code v.text;
  mark = b: if b then "✓" else "—";
  list = xs: if xs == [ ] then "none" else concatMapStringsSep ", " (x: "`${x}`") xs;

  renderOption = o: ''
    ### `${o.name}`

    ${o.description}

    **Type:** `${o.type}`
    ${optionalString (o ? default) "\n**Default:** ${value o.default}\n"}${
      optionalString (o ? example) "\n**Example:** ${value o.example}\n"
    }
  '';

  page =
    f:
    let
      p = supported f;
      section = heading: text: optionalString (text != null) "## ${heading}\n\n${text}\n";
    in
    ''
      # ${nameOf f}

      ${f.doc.summary}

      | Home | NixOS | macOS |
      |:----:|:-----:|:-----:|
      | ${mark p.home} | ${mark p.nixos} | ${mark p.darwin} |

      ${f.doc.description}
      ${section "On NixOS" (f.doc.nixos or null)}
      ${section "On macOS" (f.doc.darwin or null)}
      ## Relations

      - **Requires:** ${list (map (n: "features.${concatStringsSep "." n}") f.requiredNames)}
      - **Sets:** ${list (setsOf (argsOf contexts.nixos) f)}

      ## Options

      ${concatMapStringsSep "\n" renderOption (optionsOf f)}
      ---

      Source: `${sourceOf f}`
    '';

  byCategory = lib.groupBy categoryOf documented;

  summary = ''
    # Summary

    [Introduction](README.md)
  ''
  + concatStringsSep "" (
    lib.mapAttrsToList (
      c: fs:
      "\n# ${categoryTitle c}\n\n"
      + concatMapStringsSep "\n" (f: "- [${nameOf f}](${pathOf f})") fs
      + "\n"
    ) byCategory
  );

  bookToml = ''
    [book]
    title = "${title}"
    src = "src"
  '';

  ## The book's folder: settings, table of contents, introduction and one
  ## page per feature, each written to a file in the Nix store and linked
  ## into place.
  src = pkgs.linkFarm "${title}-docs-src" (
    [
      {
        name = "book.toml";
        path = pkgs.writeText "book.toml" bookToml;
      }
      {
        name = "src/SUMMARY.md";
        path = pkgs.writeText "SUMMARY.md" summary;
      }
      {
        name = "src/README.md";
        path = intro;
      }
    ]
    ++ map (f: {
      name = "src/${pathOf f}";
      path = pkgs.writeText "${nameOf f}.md" (page f);
    }) documented
  );
in
pkgs.runCommand "${title}-docs" { nativeBuildInputs = [ pkgs.mdbook ]; } ''
  cp -rL ${src} book
  chmod -R u+w book
  mdbook build book --dest-dir $out/html
  cp -r book/src $out/markdown
''
