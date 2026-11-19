{
  pkgs,
  emacsPackages,
  mkElispPackage,
}:

mkElispPackage pkgs emacsPackages {
  name = "tessera-json-utils";
  summary = "JSON and JSON5 editing commands";
  config = ''
    ;;; Commentary:

    ;; Editing commands for the tree-sitter JSON and JSON5 modes, the
    ;; counterparts of the list commands in tessera-javascript-utils.
    ;;
    ;; Nothing is bound by default: bind `tessera-json-utils-map' in the
    ;; modes' keymaps.

    ;;; Code:

    (require 'treesit)
    (require 'seq)
    (require 'subr-x)

    (defun tessera-json-utils--node ()
      "Return the node at point, or the one ending at point if point is on punctuation."
      (unless (treesit-parser-list)
        (user-error "No tree-sitter parser in this buffer"))
      (let ((node (treesit-node-at (point))))
        (unless (or (treesit-node-check node 'named) (bobp))
          (when-let* ((before (treesit-parent-until (treesit-node-at (1- (point)))
                                                    (lambda (n) (treesit-node-check n 'named))
                                                    t))
                      ((= (treesit-node-end before) (point))))
            (setq node before)))
        node))

    (defun tessera-json-utils--type-p (node regexp)
      "Non-nil if NODE's type matches REGEXP."
      (and node (string-match-p regexp (treesit-node-type node))))

    (defun tessera-json-utils--text (node)
      "Return the text of NODE."
      (treesit-node-text node t))

    (defun tessera-json-utils--elements (list)
      "Return the elements of LIST, an object or array node.
    Comments are left out, and so is a trailing comma, which the JSON
    grammar parses as an error or a missing element."
      (seq-remove (lambda (n) (or (member (treesit-node-type n) '("comment" "ERROR"))
                                  (treesit-node-check n 'missing)))
                  (treesit-node-children list t)))

    (defun tessera-json-utils--key (member)
      "Return the key of MEMBER, a pair (JSON) or member (JSON5), unquoted."
      (let ((key (or (treesit-node-child-by-field-name member "key")
                     (treesit-node-child-by-field-name member "name"))))
        (if (equal (treesit-node-type key) "string")
            (substring (tessera-json-utils--text key) 1 -1)
          (tessera-json-utils--text key))))

    (defun tessera-json-utils--jq-string (member)
      "Return the key of MEMBER, a pair (JSON) or member (JSON5), as a jq string."
      (let* ((key (or (treesit-node-child-by-field-name member "key")
                      (treesit-node-child-by-field-name member "name")))
             (text (tessera-json-utils--text key)))
        (pcase (and (equal (treesit-node-type key) "string") (aref text 0))
          (?\" text)
          (?'
           (concat "\""
                   (replace-regexp-in-string
                    "\\\\.\\|\"" (lambda (s) (pcase s ("\\'" "'") ("\"" "\\\"") (_ s)))
                    (substring text 1 -1) t t)
                   "\""))
          (_ (format "%S" text)))))

    (defun tessera-json-utils--replace (beg end text)
      "Replace BEG..END with TEXT and indent it."
      (save-excursion
        (goto-char beg)
        (delete-region beg end)
        (insert text)
        (indent-region beg (point))))

    (defun tessera-json-utils--list-at-point (regexp what)
      "Return the node around point whose type matches REGEXP, an object or array.
    Its elements must be uncommented.  WHAT names it in errors."
      (let ((list (or (treesit-parent-until (tessera-json-utils--node)
                                            (lambda (n) (tessera-json-utils--type-p n regexp))
                                            t)
                      (user-error "No %s at point" what))))
        (dolist (child (treesit-node-children list t))
          (pcase (treesit-node-type child)
            ("comment" (user-error "The %s has comments" what))
            ("ERROR" (unless (equal (tessera-json-utils--text child) ",")
                       (user-error "The %s has syntax errors" what)))))
        (or (tessera-json-utils--elements list)
            (user-error "The %s is empty" what))
        list))

    (defun tessera-json-utils--trailing-comma-p (list)
      "Non-nil if LIST, an object or array node without comments, ends with a comma."
      (string-search "," (buffer-substring-no-properties
                          (treesit-node-end (car (last (tessera-json-utils--elements list))))
                          (1- (treesit-node-end list)))))

    (defun tessera-json-utils-expand-node ()
      "Put each element of the object or array at point on a line of its own."
      (interactive)
      (let* ((list (tessera-json-utils--list-at-point "\\`\\(object\\|array\\)\\'" "object or array"))
             (children (treesit-node-children list)))
        (tessera-json-utils--replace
         (treesit-node-start list) (treesit-node-end list)
         (concat (tessera-json-utils--text (car children)) "\n"
                 (mapconcat #'tessera-json-utils--text (tessera-json-utils--elements list) ",\n")
                 (if (tessera-json-utils--trailing-comma-p list) "," "") "\n"
                 (tessera-json-utils--text (car (last children)))))))

    (defun tessera-json-utils-contract-node ()
      "Put the object or array at point on a single line."
      (interactive)
      (let* ((list (tessera-json-utils--list-at-point "\\`\\(object\\|array\\)\\'" "object or array"))
             (children (treesit-node-children list))
             (open (tessera-json-utils--text (car children)))
             (padding (if (equal open "{") " " "")))
        (tessera-json-utils--replace
         (treesit-node-start list) (treesit-node-end list)
         (concat open padding
                 (mapconcat #'tessera-json-utils--text (tessera-json-utils--elements list) ", ")
                 padding (tessera-json-utils--text (car (last children)))))))

    (defun tessera-json-utils-sort ()
      "Sort the members of the object at point by key.
    Only the object's own members move; the layout between them stays."
      (interactive)
      (let* ((object (tessera-json-utils--list-at-point "\\`object\\'" "object"))
             (members (tessera-json-utils--elements object))
             (edits (seq-mapn (lambda (member sorted)
                                (list (treesit-node-start member) (treesit-node-end member)
                                      (tessera-json-utils--text sorted)))
                              members
                              (seq-sort-by #'tessera-json-utils--key #'string< members)))
             (start (copy-marker (treesit-node-start object)))
             (end (copy-marker (treesit-node-end object))))
        (save-excursion
          (pcase-dolist (`(,from ,to ,text) (reverse edits))
            (goto-char from)
            (delete-region from to)
            (insert text)))
        (indent-region start end)))

    (defun tessera-json-utils-kill ()
      "Kill like `kill-line', but not past the end of the object, array or string."
      (interactive)
      (let* ((point (point))
             (container (treesit-parent-until
                         (tessera-json-utils--node)
                         (lambda (n)
                           (and (tessera-json-utils--type-p n "\\`\\(object\\|array\\|string\\)\\'")
                                (< (treesit-node-start n) point (treesit-node-end n))))
                         t))
             (limit (and container (1- (treesit-node-end container)))))
        (if (and limit (< limit (pos-eol)))
            (kill-region point (max point limit))
          (kill-line))))

    (defun tessera-json-utils-print-path ()
      "Show the jq path of the value at point and copy it."
      (interactive)
      (let ((node (tessera-json-utils--node))
            segments)
        ;; Up to a value: a member's key or value, or an array's element
        (while (and node (let ((parent (treesit-node-parent node)))
                           (not (pcase (treesit-node-type parent)
                                  ((or "pair" "member") t)
                                  ("array" (seq-contains-p (tessera-json-utils--elements parent)
                                                           node #'treesit-node-eq))))))
          (setq node (treesit-node-parent node)))
        (while-let ((parent (and node (treesit-node-parent node)))
                    ((tessera-json-utils--type-p parent "\\`\\(pair\\|member\\|array\\|object\\)\\'")))
          (pcase (treesit-node-type parent)
            ((or "pair" "member")
             (let ((key (tessera-json-utils--key parent)))
               (push (if (string-match-p "\\`[[:alpha:]_][[:alnum:]_]*\\'" key)
                         (concat "." key)
                       (concat "[" (tessera-json-utils--jq-string parent) "]"))
                     segments)))
            ("array" (push (format "[%d]" (seq-position (tessera-json-utils--elements parent)
                                                        node #'treesit-node-eq))
                           segments)))
          (setq node parent))
        (unless segments
          (user-error "Not inside an object or array"))
        (let ((path (apply #'concat segments)))
          (when (string-prefix-p "[" path)
            (setq path (concat "." path)))
          (kill-new path)
          (message "%s" path))))

    (defvar-keymap tessera-json-utils-map
      :doc "Keymap of JSON and JSON5 editing commands."
      "c" '("contract list" . tessera-json-utils-contract-node)
      "j" '("print path" . tessera-json-utils-print-path)
      "k" '("kill" . tessera-json-utils-kill)
      "s" '("sort keys" . tessera-json-utils-sort)
      "x" '("expand list" . tessera-json-utils-expand-node))
  '';
}
