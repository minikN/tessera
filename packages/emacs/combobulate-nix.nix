{
  pkgs,
  emacsPackages,
  mkElispPackage,
}:

mkElispPackage pkgs emacsPackages {
  name = "tessera-combobulate-nix";
  summary = "Nix support for Combobulate";
  packageRequires = [
    (pkgs.tessera.emacs.combobulate.override { inherit emacsPackages; })
  ];
  config = # elisp
    ''
      ;;; Commentary:

      ;; Structural navigation and editing for Nix tree-sitter buffers.

      ;;; Code:

      (require 'combobulate)
      (require 'seq)

      (defun tessera-combobulate-nix--invert-production-rules (rules)
        "Return the inverse of production RULES."
        (let ((inverse (make-hash-table :test #'equal))
              result)
          (dolist (rule rules)
            (dolist (child (seq-uniq (flatten-tree (cdr rule))))
              (when (stringp child)
                (push (car rule) (gethash child inverse)))))
          (maphash (lambda (child parents)
                     (push (list child parents) result))
                   inverse)
          result))

      (defconst tessera-combobulate-rules-nix
        '(("_expression"
           (:*unnamed* ("apply_expression" "assert_expression" "attrset_expression"
                        "binary_expression" "float_expression" "function_expression"
                        "has_attr_expression" "hpath_expression" "if_expression"
                        "indented_string_expression" "integer_expression"
                        "let_attrset_expression" "let_expression" "list_expression"
                        "parenthesized_expression" "path_expression" "rec_attrset_expression"
                        "select_expression" "spath_expression" "string_expression"
                        "unary_expression" "uri_expression" "variable_expression"
                        "with_expression")))
          ("apply_expression"
           (:*unnamed* nil :function ("_expression") :argument ("_expression")))
          ("assert_expression"
           (:*unnamed* nil :condition ("_expression") :body ("_expression")))
          ("attrpath" (:*unnamed* nil :attr ("identifier" "interpolation" "string_expression")))
          ("attrset_expression" (:*unnamed* ("binding_set")))
          ("binary_expression"
           (:*unnamed* nil :left ("_expression") :right ("_expression")))
          ("binding"
           (:*unnamed* nil :attrpath ("attrpath") :expression ("_expression")))
          ("binding_set"
           (:*unnamed* nil :binding ("binding" "inherit" "inherit_from")))
          ("comment" (:*unnamed* nil))
          ("dollar_escape" (:*unnamed* nil))
          ("ellipses" (:*unnamed* nil))
          ("escape_sequence" (:*unnamed* nil))
          ("float_expression" (:*unnamed* nil))
          ("formal" (:*unnamed* nil :name ("identifier") :default ("_expression")))
          ("formals" (:*unnamed* ("ellipses") :formal ("formal")))
          ("function_expression"
           (:*unnamed* nil
            :universal ("identifier") :formals ("formals") :body ("_expression")))
          ("has_attr_expression"
           (:*unnamed* nil :expression ("_expression") :attrpath ("attrpath")))
          ("hpath_expression" (:*unnamed* ("interpolation" "path_fragment")))
          ("identifier" (:*unnamed* nil))
          ("if_expression"
           (:*unnamed* nil
            :condition ("_expression") :consequence ("_expression")
            :alternative ("_expression")))
          ("indented_string_expression"
           (:*unnamed* ("dollar_escape" "escape_sequence" "interpolation" "string_fragment")))
          ("inherit" (:*unnamed* nil :attrs ("inherited_attrs")))
          ("inherit_from"
           (:*unnamed* nil :expression ("_expression") :attrs ("inherited_attrs")))
          ("inherited_attrs"
           (:*unnamed* nil :attr ("identifier" "interpolation" "string_expression")))
          ("integer_expression" (:*unnamed* nil))
          ("interpolation" (:*unnamed* nil :expression ("_expression")))
          ("let_attrset_expression" (:*unnamed* ("binding_set")))
          ("let_expression"
           (:*unnamed* ("binding_set") :body ("_expression")))
          ("list_expression" (:*unnamed* nil :element ("_expression")))
          ("parenthesized_expression" (:*unnamed* nil :expression ("_expression")))
          ("path_expression" (:*unnamed* ("interpolation" "path_fragment")))
          ("path_fragment" (:*unnamed* nil))
          ("rec_attrset_expression" (:*unnamed* ("binding_set")))
          ("select_expression"
           (:*unnamed* nil
            :expression ("_expression") :attrpath ("attrpath") :default ("_expression")))
          ("source_code" (:*unnamed* nil :expression ("_expression")))
          ("spath_expression" (:*unnamed* nil))
          ("string_expression"
           (:*unnamed* ("dollar_escape" "escape_sequence" "interpolation" "string_fragment")))
          ("string_fragment" (:*unnamed* nil))
          ("unary_expression" (:*unnamed* nil :argument ("_expression")))
          ("uri_expression" (:*unnamed* nil))
          ("variable_expression" (:*unnamed* nil :name ("identifier")))
          ("with_expression"
           (:*unnamed* nil :environment ("_expression") :body ("_expression")))))

      (defconst tessera-combobulate-rules-nix-types
        '("_expression" "apply_expression" "assert_expression" "attrpath"
          "attrset_expression" "binary_expression" "binding" "binding_set"
          "comment" "dollar_escape" "ellipses" "escape_sequence" "float_expression"
          "formal" "formals" "function_expression" "has_attr_expression"
          "hpath_expression" "identifier" "if_expression" "indented_string_expression"
          "inherit" "inherit_from" "inherited_attrs" "integer_expression"
          "interpolation" "let_attrset_expression" "let_expression" "list_expression"
          "parenthesized_expression" "path_expression" "path_fragment"
          "rec_attrset_expression" "select_expression" "source_code"
          "spath_expression" "string_expression" "string_fragment"
          "unary_expression" "uri_expression" "variable_expression" "with_expression"))

      (defconst tessera-combobulate-rules-nix-supertypes '("_expression"))

      (push (list 'nix tessera-combobulate-rules-nix) combobulate-rules-alist)
      (push (list 'nix (tessera-combobulate-nix--invert-production-rules tessera-combobulate-rules-nix))
            combobulate-rules-inverse-alist)
      (push (list 'nix tessera-combobulate-rules-nix-types) combobulate-rules-types-alist)
      (push (list 'nix tessera-combobulate-rules-nix-supertypes) combobulate-rules-supertypes-alist)

      (defun tessera-combobulate-nix-pretty-print-node-name (node default-name)
        "Pretty print NODE's name for Nix, falling back to DEFAULT-NAME."
        (combobulate-string-truncate
         (pcase (combobulate-node-type node)
           ("binding" (combobulate-node-text
                       (combobulate-node-child-by-field node "attrpath")))
           ((or "string_expression" "indented_string_expression")
            (combobulate-node-text node))
           (_ default-name))
         40))

      (eval-and-compile
        (defvar tessera-combobulate-nix-definitions
          '((context-nodes
             '("identifier" "string_fragment" "path_fragment"
               "integer_expression" "float_expression" "uri_expression"))
            (envelope-list nil)
            (pretty-print-node-name-function #'tessera-combobulate-nix-pretty-print-node-name)
            (procedures-edit
             `((:activation-nodes
                ((:nodes
                  ((rule "binding"))
                  :has-fields "expression"
                  :has-ancestor ((irule "binding"))))
                :selector (:choose
                           parent
                           :match-query
                           (:query (binding_set
                                    (binding attrpath: (_) expression: (_) @match)+)
                                   :engine combobulate)))
               (:activation-nodes
                ((:nodes
                  ((rule "binding"))
                  :has-fields "attrpath"
                  :has-ancestor ((irule "binding")))
                 (:nodes
                  ((rule "attrpath"))
                  :has-fields "attr"
                  :has-ancestor ((irule "binding"))))
                :selector (:choose
                           parent
                           :match-query
                           (:query (binding_set (binding attrpath: (_) @match)+)
                                   :engine combobulate)))))
            (procedures-sexp
             '((:activation-nodes
                ((:nodes ("binding" "function_expression" "let_expression"))))))
            (procedures-defun
             '((:activation-nodes
                ((:nodes ("binding" "inherit" "inherit_from"
                          "function_expression" "let_expression"))))))
            (procedures-sibling
             `((:activation-nodes
                ((:nodes
                  ((rule "list_expression"))
                  :position at
                  :has-parent ((rule "list_expression"))))
                :selector (:match-children t))
               (:activation-nodes
                ((:nodes ("binding" "inherit" "inherit_from")
                  :position at
                  :has-parent ("binding_set")))
                :selector (:match-children t))
               (:activation-nodes
                ((:nodes ("formal") :position at :has-parent ("formals")))
                :selector (:match-children t))
               (:activation-nodes
                ((:nodes
                  ((rule "binding"))
                  :has-fields "expression"
                  :has-ancestor ((irule "binding"))))
                :selector (:choose
                           parent
                           :match-query
                           (:query (binding_set
                                    (binding attrpath: (_) expression: (_) @match)+)
                                   :engine combobulate)))))
            (procedures-hierarchy
             '((:activation-nodes
                ((:nodes (exclude (all) "string_fragment" "path_fragment")
                  :position at))
                :selector (:choose node :match-children t))))
            (procedures-logical
             '((:activation-nodes ((:nodes (all)))))))))

      (define-combobulate-language
       :name nix
       :major-modes (nix-ts-mode)
       :custom tessera-combobulate-nix-definitions)
    '';
}
