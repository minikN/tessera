{
  lib,
  inputs,
  evalOptions,
  setsOf,
}:

## Build the documentation of the documented `features`: one Markdown page per
## feature, grouped by folder, and an mdBook site from them.
##
## The result has two folders:
##   $out/markdown  the generated Markdown (mdBook's source)
##   $out/html      the website built from it
##
## `(mkDocs { ... }).man` is the same documentation as a man page
## (share/man/man5/tessera.5), a separate build that doesn't need mdBook.
{
  pkgs,
  features,
}:

let
  inherit (lib) concatStringsSep concatMapStringsSep optionalString;

  ## Some facts can only be found out by evaluating the features: which
  ## platforms they support, their options and what they set. So we evaluate
  ## all features twice, once as a Linux (NixOS) host and once as a macOS
  ## host.
  evaluatedOn = {
    nixos = evalOptions {
      pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
      inherit features;
      platform = "nixos";
    };
    darwin = evalOptions {
      pkgs = inputs.nixpkgs.legacyPackages.aarch64-darwin;
      inherit features;
      platform = "darwin";
    };
  };

  ## The arguments a module function gets (`config`, `options`, ...), taken
  ## from one of the evaluations above.
  moduleArgsOf = evaluation: {
    inherit (evaluation) config options;
    inherit lib;
    pkgs = evaluation._module.args.pkgs;
  };

  ## Only features with a `doc` block get a page.
  documentedFeatures = builtins.filter (f: f.doc != null) features;

  ## The feature's name as written in a host: "emacs.keymaps".
  featureNameOf = f: concatStringsSep "." (lib.toList f.name);

  ## Where the feature lives in the repository, e.g.
  ## "features/wm/launcher/rofi.nix". `f.file` is a path in the Nix store, so
  ## we cut off everything before "features/".
  sourceFileOf =
    f:
    builtins.unsafeDiscardStringContext (
      builtins.head (builtins.match ".*/(features/.*)" (toString f.file))
    );

  ## The folder below features/ is the feature's category ("wm/launcher").
  categoryOf = f: lib.removePrefix "features/" (dirOf (sourceFileOf f));

  ## How a category is shown in the table of contents: "Wm › Launcher".
  categoryTitle =
    category:
    concatMapStringsSep " › " (s: lib.toUpper (lib.substring 0 1 s) + lib.substring 1 (-1) s) (
      lib.splitString "/" category
    );

  ## Where the feature's page goes: "wm/launcher/rofi.md".
  pagePathOf = f: "${categoryOf f}/${featureNameOf f}.md";

  supportedPlatformsOf = f: {
    homeLinux = f.supports "home" (moduleArgsOf evaluatedOn.nixos);
    homeMacos = f.supports "home" (moduleArgsOf evaluatedOn.darwin);
    nixos = f.supports "nixos" (moduleArgsOf evaluatedOn.nixos);
    darwin = f.supports "darwin" (moduleArgsOf evaluatedOn.darwin);
  };

  ## A cell of the page's platform table: "✓" or "—".
  checkmark = supported: if supported then "✓" else "—";

  ## The Home cell also says which OS it works on if it's only one of them.
  homeCheckmark =
    platforms:
    if platforms.homeLinux && platforms.homeMacos then
      "✓"
    else if platforms.homeLinux then
      "✓ (Linux)"
    else if platforms.homeMacos then
      "✓ (macOS)"
    else
      "—";

  ## Every option below `features`, as a flat list. Each entry has the
  ## option's name, description, type, default and so on. Options hidden
  ## from users are left out.
  allOptions = builtins.filter (o: o.visible && !o.internal) (
    lib.optionAttrSetToDocList evaluatedOn.nixos.options.features
  );

  ## Feature names as lists, e.g. [ "emacs" "keymaps" ].
  allFeatureNames = map (f: lib.toList f.name) features;

  ## The feature an option belongs to. Option names start with the feature
  ## name ("features.emacs.keymaps.keys.app"), but nested features make that
  ## ambiguous: both "emacs" and "emacs.keymaps" fit. The longest fitting
  ## name wins, so the option above belongs to "emacs.keymaps", not "emacs".
  ## (`o.loc` is the option name as a list; `drop 1` removes "features".)
  owningFeatureOf =
    o:
    lib.foldl' (
      best: name:
      if
        lib.take (builtins.length name) (lib.drop 1 o.loc) == name
        && builtins.length name > builtins.length best
      then
        name
      else
        best
    ) [ ] allFeatureNames;

  ## The options of one feature, its `enable` option first.
  optionsOf =
    f:
    let
      own = builtins.filter (o: owningFeatureOf o == lib.toList f.name) allOptions;
      isEnable = o: o.loc == [ "features" ] ++ lib.toList f.name ++ [ "enable" ];
    in
    builtins.filter isEnable own ++ builtins.filter (o: !isEnable o) own;

  ## Text as inline code, or as a code block if it has several lines.
  ## NOTE: We hardcode `nix` as the syntax, what if we want to print a different language?
  formatCode = text: if lib.hasInfix "\n" text then "\n\n```nix\n${text}\n```" else "`${text}`";

  ## An option's default or example: prose as it is, anything else as code.
  formatValue = v: if v._type == "literalMD" then v.text else formatCode v.text;

  ## `names` as a comma-separated list of inline code, or "none".
  formatNameList =
    names: if names == [ ] then "none" else concatMapStringsSep ", " (n: "`${n}`") names;

  ## An option rendered in MD
  ## Adding correct line break `\\\n` to type, default, example
  ## Adding double line break `\n\n` to code blocks so they start a new paragraph
  renderOption =
    o:
    let
      details = [
        "**Type:** `${o.type}`"
      ]
      ++ lib.optional (o ? default) "**Default:** ${formatValue o.default}"
      ++ lib.optional (o ? example) "**Example:** ${formatValue o.example}";
      appendDetail = text: detail: text + (if lib.hasSuffix "```" text then "\n\n" else "\\\n") + detail;
    in
    ''
      ### `${o.name}`

      ${o.description}

      ${lib.foldl' appendDetail (builtins.head details) (builtins.tail details)}
    '';

  ## A feature's page rendered in MD
  renderPage =
    f:
    let
      platforms = supportedPlatformsOf f;
      optionalSection = heading: text: optionalString (text != null) "## ${heading}\n\n${text}\n";
    in
    ''
      # ${featureNameOf f}

      ${f.doc.summary}

      | Home | NixOS | macOS |
      |:----:|:-----:|:-----:|
      | ${homeCheckmark platforms} | ${checkmark platforms.nixos} | ${checkmark platforms.darwin} |

      ${f.doc.description}
      ${optionalSection "On NixOS" (f.doc.nixos or null)}
      ${optionalSection "On macOS" (f.doc.darwin or null)}
      ## Relations

      - **Requires:** ${formatNameList (map (n: "features.${concatStringsSep "." n}") f.requiredNames)}
      - **Sets:** ${formatNameList (setsOf (moduleArgsOf evaluatedOn.nixos) f)}

      ## Options

      ${concatMapStringsSep "\n" renderOption (optionsOf f)}
      ---

      Source: `${sourceFileOf f}`
    '';

  ## The documented features grouped by category: { "wm/launcher" = [ ... ]; }
  featuresByCategory = lib.groupBy categoryOf documentedFeatures;

  tableOfContents = ''
    # Summary

    [Introduction](README.md)
  ''
  + concatStringsSep "" (
    lib.mapAttrsToList (
      category: fs:
      "\n# ${categoryTitle category}\n\n"
      + concatMapStringsSep "\n" (f: "- [${featureNameOf f}](${pagePathOf f})") fs
      + "\n"
    ) featuresByCategory
  );

  bookToml = ''
    [book]
    title = "tessera"
    src = "src"
  '';

  ## The book's folder: settings, table of contents, introduction and one
  ## page per feature, each written to a file in the Nix store and linked
  ## into place.
  bookDir = pkgs.linkFarm "tessera-docs-src" (
    [
      {
        name = "book.toml";
        path = pkgs.writeText "book.toml" bookToml;
      }
      {
        name = "src/SUMMARY.md";
        path = pkgs.writeText "SUMMARY.md" tableOfContents;
      }
      {
        name = "src/README.md";
        path = ../README.md;
      }
    ]
    ++ map (f: {
      name = "src/${pagePathOf f}";
      path = pkgs.writeText "${featureNameOf f}.md" (renderPage f);
    }) documentedFeatures
  );

  ## Converting the MD pages to one man page
  ## Print the contents of a MD `file` with its headings moved `by`
  ## levels (-1: "##" becomes "#", 1: "#" becomes "##").
  printWithShiftedHeadings =
    by: file: "pandoc -f gfm -t gfm --shift-heading-level-by=${toString by} ${file}; echo";

  ## Print a top-level heading ("# NAME").
  printSectionHeading = text: "printf '\\n# %s\\n\\n' ${lib.escapeShellArg text}";

  ## Print all pages as one Markdown document, the source of the man page.
  printCombinedMarkdown = concatStringsSep "\n" (
    [
      (printSectionHeading "NAME")
      "echo 'tessera - composable features for NixOS, nix-darwin and home-manager'"
      (printSectionHeading "DESCRIPTION")
      (printWithShiftedHeadings (-1) "${bookDir}/src/README.md")
    ]
    ++ lib.concatLists (
      lib.mapAttrsToList (
        category: fs:
        [ (printSectionHeading (categoryTitle category)) ]
        ++ map (f: printWithShiftedHeadings 1 "${bookDir}/src/${pagePathOf f}") fs
      ) featuresByCategory
    )
  );

  ## Applying man page specific changes to the md document.
  ## Pandoc supports `lua-filter` so lua makes sense here.
  ## Changes:
  ## - Uppercase headings
  ## - Strip urls from links (leaving only text)
  ## - Remove unnecessary blank lines
  manPageFilter = pkgs.writeText "man-filter.lua" ''
    function Header(h)
      if h.level == 1 then
        h.content = pandoc.text.upper(pandoc.utils.stringify(h.content))
        return h
      elseif h.level == 3 or h.level > 4 then
        return pandoc.Para({ pandoc.Strong(h.content) })
      end
    end

    function Table(t)
      return t:walk({
        Link = function(l)
          return l.content
        end,
      })
    end

    local function isTightList(b)
      if b.t ~= "BulletList" and b.t ~= "OrderedList" then
        return false
      end
      for _, item in ipairs(b.content) do
        if item[1] and item[1].t == "Para" then
          return false
        end
      end
      return true
    end

    function Pandoc(doc)
      local blocks = {}
      local function add(b)
        table.insert(blocks, b)
      end
      local i = 1
      while i <= #doc.blocks do
        local b = doc.blocks[i]
        i = i + 1
        if b.t == "Header" and b.level == 4 then
          local body = {}
          while i <= #doc.blocks and doc.blocks[i].t ~= "Header" and doc.blocks[i].t ~= "HorizontalRule" do
            table.insert(body, doc.blocks[i])
            i = i + 1
          end
          add(pandoc.DefinitionList({ { { pandoc.Strong(b.content) }, { body } } }))
        elseif isTightList(b) then
          -- keep the blank line before the list, unless it starts a section
          if i > 2 and doc.blocks[i - 2].t ~= "Header" then
            add(pandoc.RawBlock("man", ".sp"))
          end
          add(pandoc.RawBlock("man", ".PD 0"))
          add(b)
          add(pandoc.RawBlock("man", ".PD"))
        else
          add(b)
        end
      end
      doc.blocks = blocks
      return doc
    end
  '';

  ## Build the actual man page from the single MD document we create above
  ## and the applied lua filters.
  manPage = pkgs.runCommand "tessera-man" { nativeBuildInputs = [ pkgs.pandoc ]; } ''
    {
    ${printCombinedMarkdown}
    } > tessera.md
    mkdir -p $out/share/man/man5
    pandoc -f gfm -t man --standalone --lua-filter ${manPageFilter} \
      -M title=TESSERA -M section=5 tessera.md -o $out/share/man/man5/tessera.5
  '';
in
pkgs.runCommand "tessera-docs"
  {
    nativeBuildInputs = [ pkgs.mdbook ];
    passthru.man = manPage;
  }
  ''
    cp -rL ${bookDir} book
    chmod -R u+w book
    mdbook build book --dest-dir $out/html
    cp -r book/src $out/markdown
  ''
