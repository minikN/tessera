{
  pkgs,
  emacsPackages,
  mkElispPackage,
}:

mkElispPackage pkgs emacsPackages {
  name = "tessera-combobulate-json5";
  summary = "JSON5 support for Combobulate";
  packageRequires = [
    (pkgs.tessera.emacs.combobulate.override { inherit emacsPackages; })
  ];
  config = # elisp
    ''
      ;;; Commentary:

      ;; Structural navigation and editing for JSON5 tree-sitter buffers.

      ;;; Code:

      (require 'combobulate)

      (defconst tessera-combobulate-rules-json5
        '(("array" (:*unnamed* ("array" "object" "string" "number" "true" "false" "null")))
          ("comment" (:*unnamed* nil))
          ("false" (:*unnamed* nil))
          ("file" (:*unnamed* ("array" "object" "string" "number" "true" "false" "null")))
          ("identifier" (:*unnamed* nil))
          ("member" (:*unnamed* nil
                     :name ("identifier" "string")
                     :value ("array" "object" "string" "number" "true" "false" "null")))
          ("null" (:*unnamed* nil))
          ("number" (:*unnamed* nil))
          ("object" (:*unnamed* ("member")))
          ("string" (:*unnamed* nil))
          ("true" (:*unnamed* nil))))

      (defconst tessera-combobulate-rules-json5-inverse
        '(("array" ("array" "file" "member"))
          ("false" ("array" "file" "member"))
          ("identifier" ("member"))
          ("member" ("object"))
          ("null" ("array" "file" "member"))
          ("number" ("array" "file" "member"))
          ("object" ("array" "file" "member"))
          ("string" ("array" "file" "member"))
          ("true" ("array" "file" "member"))))

      (defconst tessera-combobulate-rules-json5-types
        '("array" "comment" "false" "file" "identifier" "member"
          "null" "number" "object" "string" "true"))

      (defconst tessera-combobulate-rules-json5-supertypes nil)

      (push (list 'json5 tessera-combobulate-rules-json5) combobulate-rules-alist)
      (push (list 'json5 tessera-combobulate-rules-json5-inverse) combobulate-rules-inverse-alist)
      (push (list 'json5 tessera-combobulate-rules-json5-types) combobulate-rules-types-alist)
      (push (list 'json5 tessera-combobulate-rules-json5-supertypes) combobulate-rules-supertypes-alist)

      (defun tessera-combobulate-json5-pretty-print-node-name (node default-name)
        "Pretty print NODE's name for JSON5, falling back to DEFAULT-NAME."
        (pcase (combobulate-node-type node)
          ("member" (combobulate-node-text
                     (combobulate-node-child-by-field node "name")))
          ("string" (combobulate-string-truncate (combobulate-node-text node) 40))
          (_ default-name)))

      (eval-and-compile
        (defvar tessera-combobulate-json5-definitions
          '((context-nodes
             '("string" "identifier" "number" "null" "true" "false"))
            (envelope-list
             `((:description
                "\"...\": { ... }"
                :key "o"
                :mark-node t
                :nodes ("member")
                :name "nest-member-object"
                :template
                ("\"" (p member "Member") "\": " "{" n> r> n> "}" >))
               (:description
                "[ ... ]"
                :key "a"
                :mark-node t
                :nodes ("string" "array" "object" "number" "null" "true" "false")
                :name "nest-array"
                :template
                ("[" r> "]"))))
            (pretty-print-node-name-function #'tessera-combobulate-json5-pretty-print-node-name)
            (procedures-edit
             `((:activation-nodes
                ((:nodes
                  ((rule "member"))
                  :has-fields "value"
                  :has-ancestor ((irule "member"))))
                :selector (:choose
                           parent
                           :match-query
                           (:query (object (member (_) (_) @match)+) :engine combobulate)))
               (:activation-nodes
                ((:nodes
                  ((rule "member"))
                  :has-fields "name"
                  :has-ancestor ((irule "member"))))
                :selector (:choose
                           parent
                           :match-query
                           (:query (object (member (_) @match)+) :engine combobulate)))))
            (procedures-sexp
             '((:activation-nodes ((:nodes ("member"))))))
            (procedures-defun
             '((:activation-nodes ((:nodes ("file"))))))
            (procedures-sibling
             '((:activation-nodes
                ((:nodes
                  ((rule "array"))
                  :position at
                  :has-parent ((rule "array"))))
                :selector (:match-children t))
               (:activation-nodes
                ((:nodes ("member") :position at :has-parent ("object")))
                :selector (:match-children t))
               (:activation-nodes
                ((:nodes
                  ((rule "member"))
                  :has-fields "value"
                  :has-ancestor ((irule "member"))))
                :selector (:choose
                           parent
                           :match-query
                           (:query (object (member (_) (_) @match)+) :engine combobulate)))))
            (procedures-hierarchy
             '((:activation-nodes
                ((:nodes (exclude (all) "string") :position at))
                :selector (:choose node :match-children t))))
            (procedures-logical
             '((:activation-nodes ((:nodes (all)))))))))

      (define-combobulate-language
       :name json5
       :major-modes (json5-ts-mode)
       :custom tessera-combobulate-json5-definitions)
    '';
}
