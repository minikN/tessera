{
  pkgs,
  emacsPackages,
  mkElispPackage,
  nodejs,
  pnpm,
  yarn,
  bun,
  deno,
}:

mkElispPackage pkgs emacsPackages {
  name = "tessera-javascript-utils";
  summary = "JavaScript refactorings and package commands";
  config = ''
    ;;; Commentary:

    ;; Refactorings for the tree-sitter JavaScript and TypeScript modes in
    ;; the spirit of js2-refactor, covering what Emacs and the TypeScript
    ;; language server don't, and commands for the package manager of the
    ;; package at hand (npm, pnpm, yarn, bun or deno).
    ;;
    ;; Nothing is bound by default: bind `tessera-javascript-utils-refactor-map'
    ;; in the modes' keymaps and `tessera-javascript-utils-package-map' where
    ;; `tessera-javascript-utils-package-root' finds a package.

    ;;; Code:

    (require 'treesit)
    (require 'compile)
    (require 'seq)
    (require 'subr-x)

    (defgroup tessera-javascript-utils nil
      "JavaScript refactorings and package commands."
      :group 'tessera
      :prefix "tessera-javascript-utils-")

    (defcustom tessera-javascript-utils-log-template "console.log(\"%s = \", %s);"
      "Statement `tessera-javascript-utils-log-this' inserts.
    The first %s is the expression as a string, the second the expression."
      :type 'string)

    (defcustom tessera-javascript-utils-debug-template "debug(\"%s = %%s\", %s);"
      "Statement `tessera-javascript-utils-debug-this' inserts.
    The first %s is the expression as a string, the second the expression."
      :type 'string)

    (defcustom tessera-javascript-utils-lockfiles
      '(("bun.lock" . bun)
        ("bun.lockb" . bun)
        ("pnpm-lock.yaml" . pnpm)
        ("yarn.lock" . yarn)
        ("package-lock.json" . npm))
      "Lockfiles and the tools they belong to.
    The lockfile nearest to the package decides, so workspaces with a
    lockfile at their root work too."
      :type '(alist :key-type (string :tag "Lockfile") :value-type (symbol :tag "Tool")))

    (defcustom tessera-javascript-utils-commands
      '((npm :run "${nodejs}/bin/npm run %s"
             :install "${nodejs}/bin/npm install"
             :add "${nodejs}/bin/npm install %s"
             :add-dev "${nodejs}/bin/npm install --save-dev %s"
             :remove "${nodejs}/bin/npm uninstall %s")
        (pnpm :run "${pnpm}/bin/pnpm run %s"
              :install "${pnpm}/bin/pnpm install"
              :add "${pnpm}/bin/pnpm add %s"
              :add-dev "${pnpm}/bin/pnpm add --save-dev %s"
              :remove "${pnpm}/bin/pnpm remove %s")
        (yarn :run "${yarn}/bin/yarn run %s"
              :install "${yarn}/bin/yarn install"
              :add "${yarn}/bin/yarn add %s"
              :add-dev "${yarn}/bin/yarn add --dev %s"
              :remove "${yarn}/bin/yarn remove %s")
        (bun :run "${bun}/bin/bun run --bun %s"
             :install "${bun}/bin/bun install"
             :add "${bun}/bin/bun add %s"
             :add-dev "${bun}/bin/bun add --dev %s"
             :remove "${bun}/bin/bun remove %s")
        (deno :run "${deno}/bin/deno task %s"
              :install "${deno}/bin/deno install"
              :add "${deno}/bin/deno add %s"
              :add-dev "${deno}/bin/deno add --dev %s"
              :remove "${deno}/bin/deno remove %s"))
      "Shell commands of each tool, which is called by its store path.
    %s stands for the script or the package names.  bun runs scripts with
    `--bun', so they run on bun even where they start `node'."
      :type '(alist :key-type (symbol :tag "Tool")
                    :value-type (plist :key-type (choice (const :run) (const :install)
                                                         (const :add) (const :add-dev)
                                                         (const :remove))
                                       :value-type string)))

    (defcustom tessera-javascript-utils-script-paths
      '((npm "${nodejs}/bin")
        (pnpm "${nodejs}/bin"))
      "Directories put in front of `PATH' for the scripts a tool runs.
    npm and pnpm don't give their scripts the Node.js they run on, so scripts
    that start `node' (e.g. `tsc') find this one.  yarn, bun and deno
    provide their runtime to scripts themselves."
      :type '(alist :key-type (symbol :tag "Tool") :value-type (repeat directory)))

    ;;;; Tree-sitter helpers

    (defconst tessera-javascript-utils--function-regexp
      (rx bos (or "function_declaration" "function_expression" "function"
                  "generator_function" "generator_function_declaration"
                  "arrow_function" "method_definition")
          eos)
      "Node types of functions.")

    (defconst tessera-javascript-utils--list-regexp
      (rx bos (or "object" "array" "arguments" "formal_parameters" "named_imports"
                  "export_clause" "object_pattern" "array_pattern" "type_arguments"
                  "type_parameters" "tuple_type")
          eos)
      "Node types of bracketed, comma-separated lists.")

    (defconst tessera-javascript-utils--container-regexp
      (rx bos (or "statement_block" "class_body" "switch_body" "object" "array"
                  "arguments" "formal_parameters" "parenthesized_expression"
                  "named_imports" "export_clause" "object_pattern" "array_pattern"
                  "string" "template_string")
          eos)
      "Node types `tessera-javascript-utils-kill' doesn't kill past.")

    (defun tessera-javascript-utils--node (&optional pos)
      "Return the node at POS.
    Without POS, the node at point, or the one ending at point if point is
    on punctuation, so that `foo|)' means `foo'."
      (unless (treesit-parser-list)
        (user-error "No tree-sitter parser in this buffer"))
      (let ((node (treesit-node-at (or pos (point)))))
        (unless (or pos (treesit-node-check node 'named) (bobp))
          (let ((before (treesit-node-at (1- (point)))))
            (when (and (treesit-node-check before 'named)
                       (= (treesit-node-end before) (point)))
              (setq node before))))
        node))

    (defun tessera-javascript-utils--type-p (node regexp)
      "Non-nil if NODE's type matches REGEXP."
      (and node (string-match-p regexp (treesit-node-type node))))

    (defun tessera-javascript-utils--ancestor (node regexp)
      "Return NODE or its nearest ancestor whose type matches REGEXP."
      (treesit-parent-until
       node (lambda (n) (tessera-javascript-utils--type-p n regexp)) t))

    (defun tessera-javascript-utils--statement (node)
      "Return the statement NODE is in: NODE or the ancestor directly in a block."
      (treesit-parent-until
       node
       (lambda (n)
         (tessera-javascript-utils--type-p
          (treesit-node-parent n)
          (rx bos (or "program" "statement_block" "switch_case" "switch_default") eos)))
       t))

    (defun tessera-javascript-utils--text (node)
      "Return the text of NODE."
      (treesit-node-text node t))

    (defun tessera-javascript-utils--elements (list)
      "Return the elements of LIST, a bracketed list node, without comments."
      (seq-remove (lambda (n) (equal (treesit-node-type n) "comment"))
                  (treesit-node-children list t)))

    (defun tessera-javascript-utils--replace (beg end text)
      "Replace BEG..END with TEXT and indent it."
      (save-excursion
        (goto-char beg)
        (delete-region beg end)
        (insert text)
        (indent-region beg (point))))

    (defun tessera-javascript-utils--apply (edits)
      "Apply EDITS, a list of (BEG END TEXT), from the end of the buffer on."
      (save-excursion
        (dolist (edit (sort edits (lambda (a b) (> (car a) (car b)))))
          (pcase-let ((`(,beg ,end ,text) edit))
            (goto-char beg)
            (delete-region beg end)
            (insert text)))))

    (defun tessera-javascript-utils--removal (elements index)
      "Return the edit removing element INDEX of ELEMENTS with its comma."
      (let ((element (nth index elements))
            (next (nth (1+ index) elements))
            (previous (and (> index 0) (nth (1- index) elements))))
        (cond
         (next (list (treesit-node-start element) (treesit-node-start next) ""))
         (previous (list (treesit-node-end previous) (treesit-node-end element) ""))
         (t (list (treesit-node-start element) (treesit-node-end element) "")))))

    (defun tessera-javascript-utils--append (list text)
      "Return the edit appending TEXT to LIST, a bracketed list node."
      (let ((close (1- (treesit-node-end list))))
        (list close close
              (if (tessera-javascript-utils--elements list) (concat ", " text) text))))

    (defun tessera-javascript-utils--expression ()
      "Return (BEG . END) of the region, or of the expression at point.
    Member and subscript expressions are taken up to point, so `a.b' is
    logged with point on `b' and `a' with point on `a'."
      (if (use-region-p)
          (cons (region-beginning) (region-end))
        (let ((node (tessera-javascript-utils--node)))
          (when (tessera-javascript-utils--type-p node "\\`\\(string_fragment\\|escape_sequence\\)\\'")
            (setq node (treesit-node-parent node)))
          (while (let ((parent (treesit-node-parent node)))
                   (and (tessera-javascript-utils--type-p
                         parent "\\`\\(member\\|subscript\\)_expression\\'")
                        (not (treesit-node-eq
                              node (treesit-node-child-by-field-name parent "object")))))
            (setq node (treesit-node-parent node)))
          (cons (treesit-node-start node) (treesit-node-end node)))))

    (defun tessera-javascript-utils--unparenthesize (node)
      "Return the text of NODE without enclosing parentheses."
      (if (equal (treesit-node-type node) "parenthesized_expression")
          (tessera-javascript-utils--text (treesit-node-child node 0 t))
        (tessera-javascript-utils--text node)))

    ;;;; Refactorings

    (defun tessera-javascript-utils-ternary-to-if ()
      "Turn the ternary expression at point into an `if' statement.
    The ternary has to be returned, assigned, or the value of a declaration
    of a single variable; a `const' declaration becomes a `let' one."
      (interactive)
      (let* ((ternary (or (tessera-javascript-utils--ancestor
                           (tessera-javascript-utils--node) "\\`ternary_expression\\'")
                          (user-error "No ternary expression at point")))
             (value ternary)
             (condition (tessera-javascript-utils--unparenthesize
                         (treesit-node-child-by-field-name ternary "condition")))
             (consequence (tessera-javascript-utils--text
                           (treesit-node-child-by-field-name ternary "consequence")))
             (alternative (tessera-javascript-utils--text
                           (treesit-node-child-by-field-name ternary "alternative")))
             statement prefix branch)
        (while (tessera-javascript-utils--type-p (treesit-node-parent value)
                                                 "\\`parenthesized_expression\\'")
          (setq value (treesit-node-parent value)))
        (let ((parent (treesit-node-parent value)))
          (pcase (treesit-node-type parent)
            ("return_statement"
             (setq statement parent
                   branch (lambda (v) (format "return %s;" v))))
            ((or "assignment_expression" "augmented_assignment_expression")
             (let ((left (tessera-javascript-utils--text
                          (treesit-node-child-by-field-name parent "left")))
                   (operator (if (equal (treesit-node-type parent) "assignment_expression")
                                 "="
                               (tessera-javascript-utils--text
                                (treesit-node-child-by-field-name parent "operator")))))
               (setq statement (treesit-node-parent parent)
                     branch (lambda (v) (format "%s %s %s;" left operator v)))))
            ("variable_declarator"
             (let* ((declaration (treesit-node-parent parent))
                    (kind (tessera-javascript-utils--text (treesit-node-child declaration 0)))
                    (name (tessera-javascript-utils--text
                           (treesit-node-child-by-field-name parent "name")))
                    (type (treesit-node-child-by-field-name parent "type")))
               (unless (length= (treesit-filter-child
                                 declaration
                                 (lambda (n) (equal (treesit-node-type n) "variable_declarator")))
                                1)
                 (user-error "Split the declaration first"))
               (setq statement declaration
                     prefix (format "%s %s%s;\n" (if (equal kind "const") "let" kind) name
                                    (if type (tessera-javascript-utils--text type) ""))
                     branch (lambda (v) (format "%s = %s;" name v)))))))
        (unless (and statement
                     (tessera-javascript-utils--type-p
                      statement "\\`\\(return_statement\\|expression_statement\\|lexical_declaration\\|variable_declaration\\)\\'"))
          (user-error "The ternary has to be returned, assigned or declared"))
        (tessera-javascript-utils--replace
         (treesit-node-start statement) (treesit-node-end statement)
         (format "%sif (%s) {\n%s\n} else {\n%s\n}" (or prefix "") condition
                 (funcall branch consequence) (funcall branch alternative)))))

    (defun tessera-javascript-utils--log (template)
      "Insert TEMPLATE filled with the expression at point next to its statement.
    For a parameter, the statement goes to the start of the function body;
    otherwise after a declaration or expression statement, and before any
    other statement."
      (pcase-let* ((`(,beg . ,end) (tessera-javascript-utils--expression))
                   (expression (buffer-substring-no-properties beg end))
                   (line (format template (string-replace "\"" "\\\"" expression) expression))
                   (node (tessera-javascript-utils--node beg))
                   (parameters (tessera-javascript-utils--ancestor node "\\`formal_parameters\\'")))
        (deactivate-mark)
        (save-excursion
          (if parameters
              (let ((body (treesit-node-child-by-field-name (treesit-node-parent parameters) "body")))
                (unless (tessera-javascript-utils--type-p body "\\`statement_block\\'")
                  (user-error "The function has no block body"))
                (goto-char (1+ (treesit-node-start body)))
                (insert "\n" line))
            (let ((statement (or (tessera-javascript-utils--statement node)
                                 (user-error "Not inside a statement"))))
              (if (tessera-javascript-utils--type-p
                   statement "\\`\\(expression_statement\\|lexical_declaration\\|variable_declaration\\)\\'")
                  (progn
                    (goto-char (treesit-node-end statement))
                    (insert "\n" line))
                (goto-char (treesit-node-start statement))
                (insert line "\n")
                (forward-line -1))))
          (indent-region (pos-bol) (pos-eol 2)))))

    (defun tessera-javascript-utils-log-this ()
      "Log the expression at point, or the region, with `console.log'.
    See `tessera-javascript-utils-log-template'."
      (interactive)
      (tessera-javascript-utils--log tessera-javascript-utils-log-template))

    (defun tessera-javascript-utils-debug-this ()
      "Log the expression at point, or the region, with `debug'.
    See `tessera-javascript-utils-debug-template'."
      (interactive)
      (tessera-javascript-utils--log tessera-javascript-utils-debug-template))

    (defun tessera-javascript-utils-split-string ()
      "Split the string at point in two, concatenated with `+'.
    At the place where a string was split, join it again."
      (interactive)
      (let* ((string (or (tessera-javascript-utils--ancestor
                          (tessera-javascript-utils--node) "\\`string\\'")
                         (user-error "Not inside a string")))
             (quote (char-to-string (char-after (treesit-node-start string))))
             (joint (concat quote " + " quote)))
        (unless (< (treesit-node-start string) (point) (treesit-node-end string))
          (user-error "Not inside a string"))
        (cond
         ((looking-at (regexp-quote joint))
          (delete-char (length joint)))
         ((looking-back (regexp-quote joint) (- (point) (length joint)))
          (delete-char (- (length joint))))
         (t (insert joint)))))

    (defun tessera-javascript-utils-split-declaration ()
      "Split the declaration at point into one declaration per variable."
      (interactive)
      (let* ((declaration (or (tessera-javascript-utils--ancestor
                               (tessera-javascript-utils--node)
                               "\\`\\(lexical\\|variable\\)_declaration\\'")
                              (user-error "No declaration at point")))
             (declarators (treesit-filter-child
                           declaration
                           (lambda (n) (equal (treesit-node-type n) "variable_declarator"))))
             (kind (tessera-javascript-utils--text (treesit-node-child declaration 0)))
             (export (if (tessera-javascript-utils--type-p (treesit-node-parent declaration)
                                                           "\\`export_statement\\'")
                         "export "
                       "")))
        (when (length< declarators 2)
          (user-error "The declaration has a single variable"))
        (tessera-javascript-utils--replace
         (treesit-node-start declaration) (treesit-node-end declaration)
         (string-join
          (seq-map-indexed (lambda (declarator i)
                             (format "%s%s %s;" (if (zerop i) "" export) kind
                                     (tessera-javascript-utils--text declarator)))
                           declarators)
          "\n"))))

    (defun tessera-javascript-utils--list-at-point ()
      "Return the list node at point and its elements, which must be uncommented."
      (let ((list (or (tessera-javascript-utils--ancestor
                       (tessera-javascript-utils--node) tessera-javascript-utils--list-regexp)
                      (user-error "No object, array, argument or parameter list at point"))))
        (when (treesit-filter-child list (lambda (n) (equal (treesit-node-type n) "comment")))
          (user-error "The list has comments"))
        (or (tessera-javascript-utils--elements list)
            (user-error "The list is empty"))
        list))

    (defun tessera-javascript-utils-expand-node ()
      "Put each element of the object, array or list at point on a line of its own."
      (interactive)
      (let* ((list (tessera-javascript-utils--list-at-point))
             (children (treesit-node-children list))
             (trailing (equal (treesit-node-type (car (last children 2))) ",")))
        (tessera-javascript-utils--replace
         (treesit-node-start list) (treesit-node-end list)
         (concat (tessera-javascript-utils--text (car children)) "\n"
                 (mapconcat #'tessera-javascript-utils--text
                            (tessera-javascript-utils--elements list) ",\n")
                 (if trailing "," "") "\n"
                 (tessera-javascript-utils--text (car (last children)))))))

    (defun tessera-javascript-utils-contract-node ()
      "Put the object, array or list at point on a single line."
      (interactive)
      (let* ((list (tessera-javascript-utils--list-at-point))
             (children (treesit-node-children list))
             (open (tessera-javascript-utils--text (car children)))
             (padding (if (equal open "{") " " "")))
        (tessera-javascript-utils--replace
         (treesit-node-start list) (treesit-node-end list)
         (concat open padding
                 (mapconcat #'tessera-javascript-utils--text
                            (tessera-javascript-utils--elements list) ", ")
                 padding (tessera-javascript-utils--text (car (last children)))))))

    (defun tessera-javascript-utils--function-name (function)
      "Return the name of FUNCTION, if it is declared or assigned to a variable."
      (if-let* ((name (treesit-node-child-by-field-name function "name")))
          (unless (equal (treesit-node-type function) "method_definition")
            (tessera-javascript-utils--text name))
        (let ((parent (treesit-node-parent function)))
          (when (equal (treesit-node-type parent) "variable_declarator")
            (tessera-javascript-utils--text (treesit-node-child-by-field-name parent "name"))))))

    (defun tessera-javascript-utils--local-function (name)
      "Return the function called NAME in this buffer."
      (treesit-search-subtree
       (treesit-buffer-root-node)
       (lambda (n)
         (and (tessera-javascript-utils--type-p n tessera-javascript-utils--function-regexp)
              (equal (tessera-javascript-utils--function-name n) name)))))

    (defun tessera-javascript-utils--calls (name)
      "Return the argument lists of the calls of function NAME in this buffer."
      (let (match arguments)
        (pcase-dolist (`(,capture . ,node)
                       (treesit-query-capture
                        (treesit-buffer-root-node)
                        '((call_expression function: (identifier) @function
                                           arguments: (arguments) @arguments))))
          (if (eq capture 'function)
              (setq match (equal (tessera-javascript-utils--text node) name))
            (when match (push node arguments))))
        (nreverse arguments)))

    (defun tessera-javascript-utils--parameters (function)
      "Return the parameter list node of FUNCTION, or its single bare parameter."
      (or (treesit-node-child-by-field-name function "parameters")
          (treesit-node-child-by-field-name function "parameter")))

    (defun tessera-javascript-utils-introduce-parameter (name)
      "Turn the expression at point, or the region, into parameter NAME.
    The calls of the function in this buffer pass the expression instead."
      (interactive (list (read-string "Parameter name: ")))
      (pcase-let* ((`(,beg . ,end) (tessera-javascript-utils--expression))
                   (expression (buffer-substring-no-properties beg end))
                   (function (or (tessera-javascript-utils--ancestor
                                  (tessera-javascript-utils--node beg)
                                  tessera-javascript-utils--function-regexp)
                                 (user-error "Not inside a function")))
                   (parameters (tessera-javascript-utils--parameters function))
                   (function-name (tessera-javascript-utils--function-name function)))
        (deactivate-mark)
        (tessera-javascript-utils--apply
         (append
          (list (list beg end name)
                (if (equal (treesit-node-type parameters) "formal_parameters")
                    (tessera-javascript-utils--append parameters name)
                  (list (treesit-node-start parameters) (treesit-node-end parameters)
                        (format "(%s, %s)" (tessera-javascript-utils--text parameters) name))))
          (and function-name
               (mapcar (lambda (arguments) (tessera-javascript-utils--append arguments expression))
                       (tessera-javascript-utils--calls function-name)))))))

    (defun tessera-javascript-utils--parameter-name (parameter)
      "Return PARAMETER as it is declared, without its default value."
      (pcase (treesit-node-type parameter)
        ("assignment_pattern"
         (tessera-javascript-utils--text (treesit-node-child-by-field-name parameter "left")))
        ((or "required_parameter" "optional_parameter")
         (concat (tessera-javascript-utils--text
                  (treesit-node-child-by-field-name parameter "pattern"))
                 (if-let* ((type (treesit-node-child-by-field-name parameter "type")))
                     (tessera-javascript-utils--text type)
                   "")))
        (_ (tessera-javascript-utils--text parameter))))

    (defun tessera-javascript-utils--parameter-default (parameter)
      "Return the default value of PARAMETER, if any."
      (when-let* ((value (or (treesit-node-child-by-field-name parameter "right")
                             (treesit-node-child-by-field-name parameter "value"))))
        (tessera-javascript-utils--text value)))

    (defun tessera-javascript-utils-localize-parameter ()
      "Turn a parameter into a local variable of its function.
    With point on the parameter, its value comes from the calls in this
    buffer (you choose when they differ); with point on an argument of a
    call, from that argument.  The calls lose the argument."
      (interactive)
      (let* ((node (tessera-javascript-utils--node))
             (parameters (tessera-javascript-utils--ancestor node "\\`formal_parameters\\'"))
             (arguments (and (not parameters)
                             (tessera-javascript-utils--ancestor node "\\`arguments\\'")))
             (function (cond
                        (parameters (treesit-node-parent parameters))
                        (arguments
                         (let ((callee (treesit-node-child-by-field-name
                                        (treesit-node-parent arguments) "function")))
                           (or (and (equal (treesit-node-type callee) "identifier")
                                    (tessera-javascript-utils--local-function
                                     (tessera-javascript-utils--text callee)))
                               (user-error "Can only localize parameters of functions in this buffer"))))
                        (t (user-error "Point is neither on a parameter nor on an argument"))))
             (list (or parameters arguments))
             (index (or (seq-position (tessera-javascript-utils--elements list) (point)
                                      (lambda (n pos) (<= (treesit-node-start n) pos (treesit-node-end n))))
                        (user-error "Point is not on a parameter or argument")))
             (parameter-list (treesit-node-child-by-field-name function "parameters"))
             (parameter (or (and parameter-list
                                 (nth index (tessera-javascript-utils--elements parameter-list)))
                            (user-error "The function has no such parameter")))
             (body (treesit-node-child-by-field-name function "body"))
             (function-name (tessera-javascript-utils--function-name function))
             (calls (and function-name (tessera-javascript-utils--calls function-name)))
             (value (if arguments
                        (tessera-javascript-utils--text
                         (nth index (tessera-javascript-utils--elements arguments)))
                      (let ((values (seq-uniq
                                     (delq nil
                                           (cons (tessera-javascript-utils--parameter-default parameter)
                                                 (mapcar (lambda (args)
                                                           (when-let* ((arg (nth index (tessera-javascript-utils--elements args))))
                                                             (tessera-javascript-utils--text arg)))
                                                         calls))))))
                        (if (length= values 1)
                            (car values)
                          (completing-read "Value: " values)))))
             start end)
        (unless (tessera-javascript-utils--type-p body "\\`statement_block\\'")
          (user-error "The function has no block body"))
        (setq start (copy-marker (treesit-node-start body))
              end (copy-marker (treesit-node-end body)))
        (tessera-javascript-utils--apply
         (append
          (list (list (1+ (treesit-node-start body)) (1+ (treesit-node-start body))
                      (format "\nconst %s = %s;"
                              (tessera-javascript-utils--parameter-name parameter) value))
                (tessera-javascript-utils--removal
                 (tessera-javascript-utils--elements parameter-list) index))
          (delq nil
                (mapcar (lambda (args)
                          (let ((elements (tessera-javascript-utils--elements args)))
                            (and (nth index elements)
                                 (tessera-javascript-utils--removal elements index))))
                        calls))))
        (indent-region start end)))

    (defun tessera-javascript-utils-toggle-async ()
      "Make the function at point `async', or not anymore."
      (interactive)
      (let* ((function (or (tessera-javascript-utils--ancestor
                            (tessera-javascript-utils--node)
                            tessera-javascript-utils--function-regexp)
                           (user-error "Not inside a function")))
             (async (seq-find (lambda (n) (equal (treesit-node-type n) "async"))
                              (treesit-node-children function))))
        (save-excursion
          (if async
              (delete-region (treesit-node-start async)
                             (progn (goto-char (treesit-node-end async))
                                    (skip-chars-forward " \t")
                                    (point)))
            (goto-char (treesit-node-start
                        (if (equal (treesit-node-type function) "method_definition")
                            (seq-find (lambda (n)
                                        (or (equal (treesit-node-type n) "*")
                                            (treesit-node-eq
                                             n (treesit-node-child-by-field-name function "name"))))
                                      (treesit-node-children function))
                          function)))
            (insert "async ")))))

    (defun tessera-javascript-utils-kill ()
      "Kill like `kill-line', but not past the end of the list, block or string."
      (interactive)
      (let* ((point (point))
             (container (treesit-parent-until
                         (tessera-javascript-utils--node)
                         (lambda (n)
                           (and (tessera-javascript-utils--type-p
                                 n tessera-javascript-utils--container-regexp)
                                (< (treesit-node-start n) point (treesit-node-end n))))
                         t))
             (limit (and container (1- (treesit-node-end container)))))
        (if (and limit (< limit (pos-eol)))
            (kill-region point (max point limit))
          (kill-line))))

    (defun tessera-javascript-utils--nesting ()
      "Return the block at point and the statement it belongs to, as a cons."
      (let* ((block (or (tessera-javascript-utils--ancestor
                         (tessera-javascript-utils--node) "\\`statement_block\\'")
                        (user-error "Not inside a block")))
             (statement (or (tessera-javascript-utils--statement block)
                            (user-error "The block belongs to no statement"))))
        (cons block statement)))

    (defun tessera-javascript-utils-forward-slurp (&optional n)
      "Move the N statements after the block at point into it."
      (interactive "p")
      (pcase-let* ((`(,block . ,statement) (tessera-javascript-utils--nesting))
                   (last statement))
        (dotimes (_ (or n 1))
          (setq last (or (treesit-node-next-sibling last t) last)))
        (when (treesit-node-eq last statement)
          (user-error "Nothing to slurp"))
        (let ((text (string-trim (buffer-substring-no-properties
                                  (treesit-node-end statement) (treesit-node-end last))))
              (start (copy-marker (treesit-node-start statement)))
              (close (1- (treesit-node-end block))))
          (save-excursion
            (delete-region (treesit-node-end statement) (treesit-node-end last))
            (goto-char close)
            (skip-chars-backward " \t\n")
            (insert "\n" text)
            (indent-region start (pos-eol 2))))))

    (defun tessera-javascript-utils-forward-barf (&optional n)
      "Move the last N statements of the block at point after it."
      (interactive "p")
      (pcase-let* ((`(,block . ,statement) (tessera-javascript-utils--nesting))
                   (barfed (last (treesit-node-children block t) (or n 1))))
        (unless barfed
          (user-error "Nothing to barf"))
        (let* ((beg (save-excursion
                      (goto-char (treesit-node-start (car barfed)))
                      (skip-chars-backward " \t\n")
                      (point)))
               (end (treesit-node-end (car (last barfed))))
               (text (string-trim (buffer-substring-no-properties beg end)))
               (start (copy-marker (treesit-node-start statement)))
               (after (copy-marker (treesit-node-end statement))))
          (save-excursion
            (delete-region beg end)
            (goto-char after)
            (insert "\n" text)
            (indent-region start (point))))))

    (defvar-keymap tessera-javascript-utils-slurp-repeat-map
      :doc "Repeat slurping and barfing."
      :repeat t
      ">" #'tessera-javascript-utils-forward-slurp
      "<" #'tessera-javascript-utils-forward-barf)

    (defun tessera-javascript-utils-unwrap ()
      "Replace the statement around the statement at point, or the region, with it."
      (interactive)
      (pcase-let* ((`(,beg . ,end)
                    (if (use-region-p)
                        (cons (save-excursion (goto-char (region-beginning))
                                              (skip-chars-forward " \t\n")
                                              (point))
                              (save-excursion (goto-char (region-end))
                                              (skip-chars-backward " \t\n")
                                              (point)))
                      (let ((statement (or (tessera-javascript-utils--statement
                                            (tessera-javascript-utils--node))
                                           (user-error "Not inside a statement"))))
                        (cons (treesit-node-start statement) (treesit-node-end statement)))))
                   (inner (treesit-node-on beg end))
                   (base (if (equal (treesit-node-type inner) "statement_block")
                             inner
                           (tessera-javascript-utils--statement inner)))
                   (outer (or (and base (tessera-javascript-utils--statement
                                         (treesit-node-parent base)))
                              (user-error "Nothing to unwrap"))))
        (deactivate-mark)
        (tessera-javascript-utils--replace
         (treesit-node-start outer) (treesit-node-end outer)
         (buffer-substring-no-properties beg end))))

    (defun tessera-javascript-utils-wrap-in-for-of (beg end)
      "Wrap the statements between BEG and END in a `for ... of' loop.
    Interactively, the region or the statement at point.  Point ends up
    where the iterated value goes."
      (interactive
       (if (use-region-p)
           (list (region-beginning) (region-end))
         (let ((statement (or (tessera-javascript-utils--statement (tessera-javascript-utils--node))
                              (user-error "Not inside a statement"))))
           (list (treesit-node-start statement) (treesit-node-end statement)))))
      (let ((text (string-trim (buffer-substring-no-properties beg end))))
        (deactivate-mark)
        (delete-region beg end)
        (goto-char beg)
        (insert "for (const item of ) {\n" text "\n}")
        (indent-region beg (point))
        (goto-char beg)
        (search-forward " of ")))

    (defun tessera-javascript-utils--key (node)
      "Return the path segment of object key NODE."
      (let* ((text (tessera-javascript-utils--text node))
             (name (pcase (treesit-node-type node)
                     ("string" (substring text 1 -1))
                     ("computed_property_name" nil)
                     (_ text))))
        (cond
         ((null name) text)
         ((string-match-p "\\`[[:alpha:]_$][[:alnum:]_$]*\\'" name) (concat "." name))
         ((equal (treesit-node-type node) "string") (concat "[" text "]"))
         (t (format "[%S]" name)))))

    (defun tessera-javascript-utils-print-path ()
      "Show the path to the object or array value at point and copy it."
      (interactive)
      (let ((node (tessera-javascript-utils--node))
            segments)
        ;; Up to a value: a pair's key or value, or an array's element
        (while (and node (let ((parent (treesit-node-parent node)))
                           (not (pcase (treesit-node-type parent)
                                  ("pair" t)
                                  ("array" (seq-contains-p (tessera-javascript-utils--elements parent)
                                                           node #'treesit-node-eq))))))
          (setq node (treesit-node-parent node)))
        (while-let ((parent (and node (treesit-node-parent node)))
                    ((tessera-javascript-utils--type-p parent "\\`\\(pair\\|array\\|object\\)\\'")))
          (pcase (treesit-node-type parent)
            ("pair" (push (tessera-javascript-utils--key
                           (treesit-node-child-by-field-name parent "key"))
                          segments))
            ("array" (push (format "[%d]" (seq-position (tessera-javascript-utils--elements parent)
                                                        node #'treesit-node-eq))
                           segments)))
          (setq node parent))
        (unless segments
          (user-error "Not inside an object or array"))
        (let ((path (string-remove-prefix "." (apply #'concat segments))))
          (kill-new path)
          (message "%s" path))))

    (defvar-keymap tessera-javascript-utils-refactor-map
      :doc "Keymap of JavaScript and TypeScript refactorings."
      "a" '("toggle async" . tessera-javascript-utils-toggle-async)
      "c" '("contract list" . tessera-javascript-utils-contract-node)
      "d" '("debug this" . tessera-javascript-utils-debug-this)
      "j" '("print path" . tessera-javascript-utils-print-path)
      "k" '("kill" . tessera-javascript-utils-kill)
      "l" '("log this" . tessera-javascript-utils-log-this)
      "o" '("wrap in for-of" . tessera-javascript-utils-wrap-in-for-of)
      "p" '("introduce parameter" . tessera-javascript-utils-introduce-parameter)
      "P" '("localize parameter" . tessera-javascript-utils-localize-parameter)
      "s" '("split/join string" . tessera-javascript-utils-split-string)
      "t" '("ternary to if" . tessera-javascript-utils-ternary-to-if)
      "u" '("unwrap" . tessera-javascript-utils-unwrap)
      "v" '("split declaration" . tessera-javascript-utils-split-declaration)
      "x" '("expand list" . tessera-javascript-utils-expand-node)
      ">" '("slurp" . tessera-javascript-utils-forward-slurp)
      "<" '("barf" . tessera-javascript-utils-forward-barf))

    ;;;; Packages

    (defconst tessera-javascript-utils--manifests '("package.json" "deno.json" "deno.jsonc")
      "Files marking the root of a JavaScript package.")

    (defvar tessera-javascript-utils--jsonc-syntax-table
      (let ((table (make-syntax-table)))
        (modify-syntax-entry ?/ ". 124" table)
        (modify-syntax-entry ?* ". 23b" table)
        (modify-syntax-entry ?\n ">" table)
        table)
      "Syntax table of JSONC: strings and C-style comments.")

    ;;;###autoload
    (defun tessera-javascript-utils-package-root ()
      "Return the root of the JavaScript package `default-directory' is in, or nil."
      (locate-dominating-file
       default-directory
       (lambda (dir)
         (seq-some (lambda (file) (file-exists-p (expand-file-name file dir)))
                   tessera-javascript-utils--manifests))))

    (defun tessera-javascript-utils--root ()
      "Return the root of the package at hand, or signal an error."
      (or (tessera-javascript-utils-package-root)
          (user-error "Not inside a JavaScript package")))

    (defun tessera-javascript-utils--read-json (file)
      "Return the JSON or JSONC in FILE as an alist, or nil if there is no FILE."
      (when (file-readable-p file)
        (with-temp-buffer
          (insert-file-contents file)
          (with-syntax-table tessera-javascript-utils--jsonc-syntax-table
            (goto-char (point-min))
            (while (re-search-forward "/[/*]" nil t)
              (let ((beg (match-beginning 0)))
                (unless (save-excursion (nth 3 (syntax-ppss beg)))
                  (goto-char beg)
                  (forward-comment 1)
                  (delete-region beg (point)))))
            (goto-char (point-min))
            (while (re-search-forward ",\\([ \t\n]*[]}]\\)" nil t)
              (unless (save-excursion (nth 3 (syntax-ppss (match-beginning 0))))
                (replace-match "\\1"))))
          (goto-char (point-min))
          (json-parse-buffer :object-type 'alist :array-type 'list
                             :null-object nil :false-object nil))))

    (defun tessera-javascript-utils--manifest (root &optional deno)
      "Return the package.json at ROOT, or with DENO non-nil its deno.json."
      (if deno
          (seq-some (lambda (file) (tessera-javascript-utils--read-json (expand-file-name file root)))
                    '("deno.json" "deno.jsonc"))
        (tessera-javascript-utils--read-json (expand-file-name "package.json" root))))

    (defun tessera-javascript-utils--tool (root)
      "Return the tool managing the package at ROOT.
    The `packageManager' field of package.json decides, then a deno.json,
    then the nearest of `tessera-javascript-utils-lockfiles'; npm otherwise."
      (let ((declared (alist-get 'packageManager (tessera-javascript-utils--manifest root))))
        (or (and (stringp declared)
                 (let ((tool (intern (car (split-string declared "@")))))
                   (and (assq tool tessera-javascript-utils-commands) tool)))
            (and (seq-some (lambda (file) (file-exists-p (expand-file-name file root)))
                           '("deno.json" "deno.jsonc"))
                 'deno)
            (cdar (sort (delq nil (mapcar (pcase-lambda (`(,file . ,tool))
                                            (when-let* ((dir (locate-dominating-file root file)))
                                              (cons (length (expand-file-name dir)) tool)))
                                          tessera-javascript-utils-lockfiles))
                        (lambda (a b) (> (car a) (car b)))))
            'npm)))

    (defun tessera-javascript-utils--command (tool action &rest args)
      "Return the shell command of TOOL for ACTION, with ARGS."
      (let ((template (or (plist-get (alist-get tool tessera-javascript-utils-commands) action)
                          (user-error "No %s command for %s" action tool))))
        (if args
            (format template (mapconcat #'shell-quote-argument args " "))
          template)))

    (defun tessera-javascript-utils--compile (root action &rest args)
      "Run ACTION with ARGS by the tool of the package at ROOT.
    The command runs in ROOT, in a compilation buffer of its own, without
    colour escape codes.  Its scripts get the tool's
    `tessera-javascript-utils-script-paths' in front of `PATH', set by the
    command itself, as shells like zsh may reset `PATH' at startup."
      (let* ((tool (tessera-javascript-utils--tool root))
             (command (apply #'tessera-javascript-utils--command tool action args))
             (dirs (alist-get tool tessera-javascript-utils-script-paths))
             (default-directory root)
             ;; TERM=dumb for yarn 1, which ignores NO_COLOR, and npm's spinner
             (compilation-environment (append '("NO_COLOR=1" "TERM=dumb") compilation-environment)))
        (compilation-start
         (if dirs
             (format "env PATH=%s:\"$PATH\" %s"
                     (mapconcat #'shell-quote-argument dirs ":") command)
           command)
         nil
         (lambda (_mode)
           (format "*%s: %s*" (file-name-nondirectory (directory-file-name root))
                   (replace-regexp-in-string "\\`[^ ]*/" "" command))))))

    (defun tessera-javascript-utils--scripts (root)
      "Return the scripts and tasks of the package at ROOT as (NAME . COMMAND)."
      (mapcar (pcase-lambda (`(,name . ,value))
                (cons (symbol-name name)
                      (if (stringp value) value (alist-get 'command value))))
              (append (alist-get 'tasks (tessera-javascript-utils--manifest root t))
                      (alist-get 'scripts (tessera-javascript-utils--manifest root)))))

    (defun tessera-javascript-utils--read-script (root)
      "Read the name of a script of the package at ROOT."
      (let* ((scripts (or (tessera-javascript-utils--scripts root)
                          (user-error "The package has no scripts")))
             (width (apply #'max (mapcar (lambda (script) (string-width (car script))) scripts)))
             (completion-extra-properties
              (list :annotation-function
                    (lambda (name)
                      (concat (make-string (- (+ width 2) (string-width name)) ?\s)
                              (propertize (or (cdr (assoc name scripts)) "")
                                          'face 'completions-annotations))))))
        (completing-read "Run script: " scripts nil t)))

    (defun tessera-javascript-utils--dependencies (root)
      "Return the names of the dependencies of the package at ROOT."
      (let ((manifest (tessera-javascript-utils--manifest root)))
        (mapcar (lambda (entry) (symbol-name (car entry)))
                (append (alist-get 'dependencies manifest)
                        (alist-get 'devDependencies manifest)
                        (alist-get 'imports (tessera-javascript-utils--manifest root t))))))

    ;;;###autoload
    (defun tessera-javascript-utils-run (script)
      "Run SCRIPT of the package at hand with its package manager."
      (interactive (list (tessera-javascript-utils--read-script (tessera-javascript-utils--root))))
      (let ((root (tessera-javascript-utils--root)))
        (tessera-javascript-utils--compile root :run script)))

    ;;;###autoload
    (defun tessera-javascript-utils-install ()
      "Install the dependencies of the package at hand."
      (interactive)
      (let ((root (tessera-javascript-utils--root)))
        (tessera-javascript-utils--compile root :install)))

    ;;;###autoload
    (defun tessera-javascript-utils-add (packages)
      "Add PACKAGES to the dependencies of the package at hand."
      (interactive (list (split-string (read-string "Add packages: ") nil t)))
      (let ((root (tessera-javascript-utils--root)))
        (apply #'tessera-javascript-utils--compile root :add packages)))

    ;;;###autoload
    (defun tessera-javascript-utils-add-dev (packages)
      "Add PACKAGES to the development dependencies of the package at hand."
      (interactive (list (split-string (read-string "Add development packages: ") nil t)))
      (let ((root (tessera-javascript-utils--root)))
        (apply #'tessera-javascript-utils--compile root :add-dev packages)))

    ;;;###autoload
    (defun tessera-javascript-utils-remove (packages)
      "Remove PACKAGES from the dependencies of the package at hand."
      (interactive
       (list (completing-read-multiple
              "Remove packages: "
              (tessera-javascript-utils--dependencies (tessera-javascript-utils--root)) nil t)))
      (let ((root (tessera-javascript-utils--root)))
        (apply #'tessera-javascript-utils--compile root :remove packages)))

    ;;;###autoload
    (defun tessera-javascript-utils-visit ()
      "Visit the package.json or deno.json of the package at hand."
      (interactive)
      (let ((root (tessera-javascript-utils--root)))
        (find-file
         (seq-find #'file-exists-p
                   (mapcar (lambda (file) (expand-file-name file root))
                           (if (eq (tessera-javascript-utils--tool root) 'deno)
                               '("deno.json" "deno.jsonc" "package.json")
                             tessera-javascript-utils--manifests))))))

    (defvar-keymap tessera-javascript-utils-package-map
      :doc "Keymap of package manager commands for the package at hand."
      "a" '("add" . tessera-javascript-utils-add)
      "d" '("add dev" . tessera-javascript-utils-add-dev)
      "i" '("install" . tessera-javascript-utils-install)
      "r" '("run script" . tessera-javascript-utils-run)
      "u" '("remove" . tessera-javascript-utils-remove)
      "v" '("visit manifest" . tessera-javascript-utils-visit))
  '';
}
