{
  lib,
  platform,
  expect,
  check,
  emacsCheck,
  ...
}:

let
  packages = home: home.programs.emacs.finalPackage.explicitRequires;
  languageExtensions = {
    json = "tessera-combobulate-json5";
    nix = "tessera-combobulate-nix";
  };
  languageOnly =
    language:
    let
      extension = languageExtensions.${language};
      otherExtensions = lib.attrValues (removeAttrs languageExtensions [ language ]);
    in
    check {
      platform = platform;
      features = {
        emacs.enable = true;
        emacs.treesit.enable = true;
        ${language}.enable = true;
      };
      assertions =
        { home, ... }:
        [
          {
            assertion = lib.any (p: p.pname or "" == extension) (packages home);
            message = "${language} installs ${extension}";
          }
        ]
        ++ map (otherExtension: {
          assertion = !(lib.any (p: p.pname or "" == otherExtension) (packages home));
          message = "${language} does not install ${otherExtension}";
        }) otherExtensions;
    };
in
lib.mapAttrs' (
  language: _: lib.nameValuePair "${language}-only" (languageOnly language)
) languageExtensions
// {
  wiring = emacsCheck {
    platform = platform;
    features = {
      emacs.enable = true;
      emacs.keymaps.enable = true;
      emacs.treesit.enable = true;
      javascript.enable = true;
      json.enable = true;
      nix.enable = true;
    };
    script = # elisp
      ''
        (setq treesit-auto-install-grammar 'never)
        (require 'tessera-keymaps)
        (require 'tessera-treesit)
        (require 'which-key)

        (defun tessera-test-raw-binding (map key)
          (let ((events (listify-key-sequence (kbd key))))
            (while (cdr events)
              (setq map (lookup-key map (vector (car events))))
              (setq events (cdr events))
              (unless (keymapp map)
                (error "Missing prefix in %s" key)))
            (let ((event (car events)) result)
              (map-keymap (lambda (k binding)
                            (when (equal k event) (setq result binding)))
                          map)
              result)))

        (defun tessera-test-check-map (map expected-count)
          (let ((count 0))
            (map-keymap
             (lambda (key binding)
               (setq count (1+ count))
               (unless (and (consp binding)
                            (stringp (car binding))
                            (or (commandp (cdr binding)) (keymapp (cdr binding))))
                 (error "Undescribed binding %s: %S" key binding)))
             map)
            (unless (= count expected-count)
              (error "Expected %d bindings, found %d" expected-count count))))

        (defun tessera-test-mode (mode language text)
          (with-temp-buffer
            (insert text)
            (funcall mode)
            (unless (symbol-value (combobulate-get 'minor-mode language))
              (error "Combobulate did not activate in %s" mode))
            (unless (eq (combobulate-primary-language) language)
              (error "Wrong Combobulate language in %s" mode))))

        (unless (equal combobulate-key-prefix "C-c c o")
          (error "Wrong Combobulate prefix: %s" combobulate-key-prefix))
        (unless (featurep 'tessera-combobulate-json5)
          (error "JSON5 support was not loaded"))
        (unless (featurep 'tessera-combobulate-nix)
          (error "Nix support was not loaded"))
        (unless (and (null combobulate-javascript-highlight-queries-default)
                     (null combobulate-typescript-highlight-queries-default)
                     (null combobulate-tsx-highlight-queries-default))
          (error "Incompatible highlighting queries are enabled"))

        (tessera-test-check-map combobulate-options-key-map 6)
        (tessera-test-check-map combobulate-cursor-edit-key-map 5)
        (tessera-test-check-map combobulate-xref-key-map 1)
        (tessera-test-check-map combobulate-highlight-key-map 3)
        (tessera-test-check-map combobulate-query-key-map 3)

        (dolist (registration combobulate-registered-languages-alist)
          (let* ((language (car registration))
                 (map (symbol-value (combobulate-get 'map language)))
                 (bindings (which-key--get-keymap-bindings map nil (kbd "C-c c"))))
            (when (lookup-key map (kbd "C-c o"))
              (error "Default Combobulate prefix remains for %s" language))
            (unless (equal (cdr (assoc "C-c c o" bindings)) "group:combobulate")
              (error "Wrong prefix description for %s: %S" language bindings))
            (if (combobulate-read envelope-list language)
                (unless (keymapp (lookup-key map (kbd "C-c c o e")))
                  (error "Envelope prefix missing for %s" language))
              (when (lookup-key map (kbd "C-c c o e"))
                (error "Empty envelope prefix remains for %s" language)))))

        (let ((combobulate-flash-node nil))
          (tessera-test-mode 'js-ts-mode 'javascript "const value = 1;")
          (tessera-test-mode 'typescript-ts-mode 'typescript "const value = 1;")
          (tessera-test-mode 'tsx-ts-mode 'tsx "const value = <div />;")
          (tessera-test-mode 'json-ts-mode 'json "{\"value\": 1}")
          (tessera-test-mode 'json5-ts-mode 'json5 "{value: 1}")
          (tessera-test-mode 'nix-ts-mode 'nix "{ value = 1; }")

          (with-temp-buffer
            (insert "{first: 1}")
            (json5-ts-mode)
            (dolist (key '("a" "o" "("))
              (let ((binding (tessera-test-raw-binding combobulate-json5-envelope-map key)))
                (unless (and (consp binding)
                             (stringp (car binding))
                             (commandp (cdr binding)))
                  (error "Undescribed JSON5 envelope %s: %S" key binding))))))

        (princ "Treesit behavior is correct\n")
      '';
  };

  without-languages = check {
    platform = platform;
    features = {
      emacs.enable = true;
      emacs.treesit.enable = true;
    };
    assertions =
      { home, ... }:
      [
        {
          assertion = lib.any (p: p.pname or "" == "combobulate") (packages home);
          message = "treesit installs Combobulate without language features";
        }
        {
          assertion =
            !(lib.any (p: lib.elem (p.pname or "") (lib.attrValues languageExtensions)) (packages home));
          message = "No Combobulate extensions are installed without language features";
        }
      ];
  };

  without-keymaps = emacsCheck {
    platform = platform;
    features = {
      emacs.enable = true;
      emacs.keymaps.enable = false;
      emacs.treesit.enable = true;
      json.enable = true;
      nix.enable = true;
    };
    script = # elisp
      ''
        (require 'tessera-treesit)
        (when (featurep 'tessera-keymaps)
          (error "Treesit loaded keymaps even though they are disabled"))
        (when (fboundp 'tessera-combobulate--describe-envelope)
          (error "Treesit installed descriptions without keymaps"))
        (dolist (registration combobulate-registered-languages-alist)
          (let* ((language (car registration))
                 (map (symbol-value (combobulate-get 'map language))))
            (when (lookup-key map (kbd "C-c o"))
              (error "Default Combobulate prefix remains for %s" language))
            (if (combobulate-read envelope-list language)
                (unless (keymapp (lookup-key map (kbd "C-c c o e")))
                  (error "Envelope prefix missing for %s" language))
              (when (lookup-key map (kbd "C-c c o e"))
                (error "Empty envelope prefix remains for %s" language)))))
        (princ "Treesit works without keymaps\n")
      '';
  };

  disabled = check {
    platform = platform;
    features = {
      emacs.enable = true;
      javascript.enable = true;
      json.enable = true;
      nix.enable = true;
    };
    assertions =
      { home, ... }:
      [
        {
          assertion = !(lib.any (p: p.pname or "" == "combobulate") (packages home));
          message = "Combobulate is only installed with the treesit feature";
        }
      ];
  };

  without-tree-sitter = expect {
    platform = platform;
    features =
      { pkgs, ... }:
      {
        emacs.enable = true;
        emacs.package = pkgs.emacs.override { withTreeSitter = false; };
        emacs.treesit.enable = true;
      };
    messages = [ "features.emacs.treesit needs features.emacs.package built with tree-sitter" ];
  };
}
