{
  lib,
  inputs,
  evalOptions,
  setsOf,
}:

## Build the documentation. The result has two folders:
##   $out/markdown  the generated Markdown
##   $out/html      the website built from it
##
## `(mkDocs { ... }).man`: man pages (share/man/man5/tessera.5)
## `(mkDocs { ... }).info`: info manual
{
  pkgs,
  features,
  sourceUrl ? null,
}:

let
  inherit (lib) concatStringsSep concatMapStringsSep optionalString;

  ## We need to evaluate the features twice for each platform to find out
  ## what platform they support; what options they take
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

  ## The arguments a module function gets (`config`, `options`, ...)
  moduleArgsOf = evaluation: {
    inherit (evaluation) config options;
    inherit lib;
    pkgs = evaluation._module.args.pkgs;
  };

  ## Filter features that don't have documentation
  documentedFeatures = builtins.filter (f: f.doc != null) features;

  featureNameOf = f: concatStringsSep "." (lib.toList f.name);

  ## Path of the feature (e.g. "wm/launcher/rofi.nix")
  sourceFileOf =
    f:
    builtins.unsafeDiscardStringContext (
      builtins.head (builtins.match ".*/(features/.*)" (toString f.file))
    );

  ## The source path at the end of a page, a link if `sourceUrl` is set
  sourceLinkOf =
    f:
    if sourceUrl == null then
      "`${sourceFileOf f}`"
    else
      "[`${sourceFileOf f}`](${sourceUrl}/${sourceFileOf f})";

  ## using a the feature path as its category (e.g. rofi: wm/launcher)
  categoryOf = f: lib.removePrefix "features/" (dirOf (sourceFileOf f));

  categoryTitle =
    category:
    concatMapStringsSep " › " (s: lib.toUpper (lib.substring 0 1 s) + lib.substring 1 (-1) s) (
      lib.splitString "/" category
    );

  pagePathOf = f: "${categoryOf f}/${featureNameOf f}.md";

  supportedPlatformsOf = f: {
    homeLinux = f.supports "home" (moduleArgsOf evaluatedOn.nixos);
    homeMacos = f.supports "home" (moduleArgsOf evaluatedOn.darwin);
    nixos = f.supports "nixos" (moduleArgsOf evaluatedOn.nixos);
    darwin = f.supports "darwin" (moduleArgsOf evaluatedOn.darwin);
  };

  checkmark = supported: if supported then "✓" else "—";

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

  ## Flat list of user-facing options
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

  ## The options of a feature
  optionsOf =
    f:
    let
      own = builtins.filter (o: owningFeatureOf o == lib.toList f.name) allOptions;
      isEnable = o: o.loc == [ "features" ] ++ lib.toList f.name ++ [ "enable" ];
    in
    builtins.filter isEnable own ++ builtins.filter (o: !isEnable o) own;

  formatCode = text: if lib.hasInfix "\n" text then "\n\n```nix\n${text}\n```" else "`${text}`";
  formatValue = v: if v._type == "literalMD" then v.text else formatCode v.text;

  ## `names` as a comma-separated list of inline code, or "none".
  formatNameList =
    names: if names == [ ] then "none" else concatMapStringsSep ", " (n: "`${n}`") names;

  ## An option rendered in MD
  ## - adding correct line break `\\\n` to type, default, example
  ## - adding double line break `\n\n` to code blocks so they start a new paragraph
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
    # markdown
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
    # markdown
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

      Source: ${sourceLinkOf f}
    '';

  ## features grouped by category
  featuresByCategory = lib.groupBy categoryOf documentedFeatures;

  tableOfContents = # markdown
  ''
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

  bookToml = # toml
    ''
      [book]
      title = "tessera"
      src = "src"
    '';

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

  ## MD page to man page / info manual
  ## Print the contents of a MD `file` with its headings moved `by`
  ## levels (-1: "##" becomes "#", 1: "#" becomes "##").
  printWithShiftedHeadings =
    by: file: "pandoc -f gfm -t gfm --shift-heading-level-by=${toString by} ${file}; echo";

  printSectionHeading = text: "printf '\\n# %s\\n\\n' ${lib.escapeShellArg text}";

  ## Print all pages as one Markdown document, the source of the man page and
  ## the Info manual: the README's sections, then a top-level heading per
  ## category with its features below it.
  printCombinedMarkdown = concatStringsSep "\n" (
    [ (printWithShiftedHeadings (-1) "${bookDir}/src/README.md") ]
    ++ lib.concatLists (
      lib.mapAttrsToList (
        category: fs:
        [ (printSectionHeading (categoryTitle category)) ]
        ++ map (f: printWithShiftedHeadings 1 "${bookDir}/src/${pagePathOf f}") fs
      ) featuresByCategory
    )
  );

  ## Remove the README's badges (linked images) from the man page and the
  ## Info manual.
  dropBadgesFilter =
    pkgs.writeText "drop-badges.lua" # lua
      ''
        function Para(p)
          for _, el in ipairs(p.content) do
            local isBadge = el.t == "Link" and #el.content == 1 and el.content[1].t == "Image"
            if not (isBadge or el.t == "Space" or el.t == "SoftBreak") then
              return nil
            end
          end
          return {}
        end
      '';

  ## Applying man page specific changes to the md document.
  ## Changes:
  ## - uppercase headings
  ## - strip urls from links (leaving only text)
  ## - remove unnecessary blank lines
  manPageFilter =
    pkgs.writeText "man-filter.lua" # lua
      ''
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

  ## Build the actual man page from the single MD document create above and the applied filters
  manPage =
    pkgs.runCommand "tessera-man" { nativeBuildInputs = [ pkgs.pandoc ]; } # bash
      ''
        {
        ${printSectionHeading "NAME"}
        echo 'tessera - composable features for NixOS, nix-darwin and home-manager'
        ${printSectionHeading "DESCRIPTION"}
        ${printCombinedMarkdown}
        } > tessera.md
        mkdir -p $out/share/man/man5
        pandoc -f gfm -t man --standalone --lua-filter ${dropBadgesFilter} --lua-filter ${manPageFilter} \
          -M title=TESSERA -M section=5 tessera.md -o $out/share/man/man5/tessera.5
      '';

  ## Changes for the Info manual
  ## - sections and the categories become chapters
  ## - Headings become bold lines
  ## - Links to websites plain Texinfo
  ## - Code blocks as @example
  infoFilter =
    pkgs.writeText "info-filter.lua" # lua
      ''
        local function escape(text)
          return (text:gsub("[@{}]", "@%0"):gsub(",", "@comma{}"))
        end

        function Header(h)
          if h.level > 2 then
            return pandoc.Para({ pandoc.Strong(h.content) })
          end
          local command = h.level == 1 and "@chapter " or "@section "
          return pandoc.RawBlock("texinfo", command .. escape(pandoc.utils.stringify(h.content)))
        end

        function Link(l)
          if l.target:find("://") then
            local text = escape(pandoc.utils.stringify(l.content))
            return pandoc.RawInline("texinfo", "@uref{" .. escape(l.target) .. ", " .. text .. "}")
          end
        end

        function CodeBlock(c)
          return pandoc.RawBlock("texinfo", "@example\n" .. escape(c.text) .. "\n@end example\n@sp 1")
        end

        function HorizontalRule()
          return {}
        end
      '';

  ## The manual's entry in Info's directory
  infoDirEntry =
    pkgs.writeText "dir-entry.texi" # texinfo
      ''
        @dircategory Tessera
        @direntry
        * Tessera: (tessera).           Composable features for NixOS, nix-darwin and home-manager.
        @end direntry
      '';

  ## Build the Info manual from the same MD document and its `dir` file
  infoManual =
    pkgs.runCommand "tessera-info"
      {
        nativeBuildInputs = [
          pkgs.pandoc
          pkgs.texinfo
        ];
      } # bash
      ''
        {
        ${printCombinedMarkdown}
        } > tessera.md
        pandoc -f gfm -t texinfo --standalone --lua-filter ${dropBadgesFilter} --lua-filter ${infoFilter} \
          --include-in-header ${infoDirEntry} -M title=tessera tessera.md -o tessera.texi
        mkdir -p $out/share/info
        makeinfo --no-split tessera.texi -o $out/share/info/tessera.info \
          -c TREE_TRANSFORMATIONS=insert_nodes_for_sectioning_commands,complete_tree_nodes_menus
        install-info $out/share/info/tessera.info $out/share/info/dir
      '';
in
pkgs.runCommand "tessera-docs"
  {
    nativeBuildInputs = [ pkgs.mdbook ];
    passthru = {
      man = manPage;
      info = infoManual;
    };
  } # bash
  ''
    cp -rL ${bookDir} book
    chmod -R u+w book
    mdbook build book --dest-dir $out/html
    cp -r book/src $out/markdown
  ''
