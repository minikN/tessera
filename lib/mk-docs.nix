{ lib, inputs, evalDocs, setsOf, optionBlocks, readsOf }:

## Build the documentation of the documented `features`: one Markdown page per
## feature, grouped by folder, and an mdBook site from them.
{ pkgs, features, title ? "tessera", intro ? ../README.md }:

let
  inherit (lib) concatStringsSep concatMapStringsSep optionalString;

  ## One docs evaluation per system, to tell which platforms a feature supports.
  contexts = {
    nixos = evalDocs { pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux; inherit features; platform = "nixos"; };
    darwin = evalDocs { pkgs = inputs.nixpkgs.legacyPackages.aarch64-darwin; inherit features; platform = "darwin"; };
  };
  argsOf = e: { inherit (e) config options; inherit lib; pkgs = e._module.args.pkgs; };

  documented = builtins.filter (f: f.doc != null) features;
  nameOf = f: concatStringsSep "." (lib.toList f.name);

  ## "features/wm/launcher/rofi.nix", from the store path of the module.
  sourceOf = f: builtins.unsafeDiscardStringContext
    (builtins.head (builtins.match ".*/(features/.*)" (toString f.file)));
  categoryOf = f: lib.removePrefix "features/" (dirOf (sourceOf f));
  categoryTitle = c: concatMapStringsSep " › "
    (s: lib.toUpper (lib.substring 0 1 s) + lib.substring 1 (-1) s) (lib.splitString "/" c);
  pathOf = f: "${categoryOf f}/${nameOf f}.md";

  supported = f: {
    home = lib.any (e: f.supports "home" (argsOf e)) [ contexts.nixos contexts.darwin ];
    nixos = f.supports "nixos" (argsOf contexts.nixos);
    darwin = f.supports "darwin" (argsOf contexts.darwin);
  };

  ## An option belongs to the most specific feature whose name prefixes it.
  options = builtins.filter (o: o.visible && !o.internal)
    (lib.optionAttrSetToDocList contexts.nixos.options.features);
  names = map (f: lib.toList f.name) features;
  ownerOf = o: lib.foldl'
    (best: n: if lib.take (builtins.length n) (lib.drop 1 o.loc) == n
      && builtins.length n > builtins.length best then n else best) [ ] names;
  optionsOf = f:
    let own = builtins.filter (o: ownerOf o == lib.toList f.name) options; in
    builtins.filter (o: lib.last o.loc == "enable") own ++ builtins.filter (o: lib.last o.loc != "enable") own;

  ## What other features read, e.g. "features.theme.scheme.withHashtag".
  readElsewhere = builtins.concatMap (g: readsOf g.file g.name) features;
  usedElsewhere = path: builtins.any
    (r: r == path || lib.hasPrefix "${path}." r || lib.hasPrefix "${r}." path) readElsewhere;

  ## The systems an option is limited to: only the `nixos`/`darwin` blocks use
  ## it, no other feature reads it, and the feature isn't limited to them already.
  optionPlatforms = f: o:
    let
      rel = lib.drop (1 + builtins.length (lib.toList f.name)) o.loc;
      blocks = optionBlocks f.file f.name (concatStringsSep "." rel);
      systems = builtins.filter (s: builtins.elem s blocks) [ "nixos" "darwin" ];
      p = supported f;
    in
    if rel == [ "enable" ] || builtins.any (s: lib.hasPrefix "<" s || s == "*") rel
      || builtins.elem "home" blocks || builtins.elem "globals" blocks || usedElsewhere o.name
      || (!p.home && builtins.filter (s: p.${s}) [ "nixos" "darwin" ] == systems)
    then [ ] else systems;
  platformLabel = f: o:
    let ps = optionPlatforms f o; in
    optionalString (ps != [ ])
      " (${concatMapStringsSep ", " (s: { nixos = "NixOS"; darwin = "macOS"; }.${s}) ps})";

  code = text: if lib.hasInfix "\n" text then "\n\n```nix\n${text}\n```" else "`${text}`";
  value = v: if v._type == "literalMD" then v.text else code v.text;
  mark = b: if b then "✓" else "—";
  list = xs: if xs == [ ] then "none" else concatMapStringsSep ", " (x: "`${x}`") xs;

  renderOption = f: o: ''
    ### `${o.name}`${platformLabel f o}

    ${o.description}

    **Type:** `${o.type}`
    ${optionalString (o ? default) "\n**Default:** ${value o.default}\n"}${optionalString (o ? example) "\n**Example:** ${value o.example}\n"}
  '';

  page = f:
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
      - **Reads:** ${list f.doc.reads}
      - **Sets:** ${list (setsOf (argsOf contexts.nixos) f)}

      ## Options

      ${concatMapStringsSep "\n" (renderOption f) (optionsOf f)}
      ---

      Source: `${sourceOf f}`
    '';

  byCategory = lib.groupBy categoryOf documented;

  summary = ''
    # Summary

    [Introduction](README.md)
  '' + concatStringsSep "" (lib.mapAttrsToList
    (c: fs: "\n# ${categoryTitle c}\n\n" + concatMapStringsSep "\n" (f: "- [${nameOf f}](${pathOf f})") fs + "\n")
    byCategory);

  bookToml = ''
    [book]
    title = "${title}"
    src = "src"
  '';

  src = pkgs.linkFarm "${title}-docs-src" ([
    { name = "book.toml"; path = pkgs.writeText "book.toml" bookToml; }
    { name = "src/SUMMARY.md"; path = pkgs.writeText "SUMMARY.md" summary; }
    { name = "src/README.md"; path = intro; }
  ] ++ map (f: { name = "src/${pathOf f}"; path = pkgs.writeText "${nameOf f}.md" (page f); }) documented);
in
pkgs.runCommand "${title}-docs" { nativeBuildInputs = [ pkgs.mdbook ]; } ''
  cp -rL ${src} book
  chmod -R u+w book
  mdbook build book --dest-dir $out/html
  cp -r book/src $out/markdown
''
