;;; combobulate-nix.el --- Nix Combobulate tests  -*- lexical-binding: t; -*-

(require 'combobulate-nix)
(require 'nix-ts-mode)

(setq treesit-auto-install-grammar 'never)

(defmacro combobulate-nix-test--with-buffer (text &rest body)
  (declare (indent 1))
  `(with-temp-buffer
     (insert ,text)
     (nix-ts-mode)
     (combobulate-mode 1)
     (transient-mark-mode 1)
     (let ((combobulate-flash-node nil))
       ,@body)))

(defun combobulate-nix-test--goto (text)
  (goto-char (point-min))
  (search-forward text)
  (goto-char (match-beginning 0)))

(defun combobulate-nix-test--node (&optional types)
  (combobulate-node-at-point types))

(defun combobulate-nix-test--matched-texts (procedure node)
  (mapcar #'combobulate-node-text
          (combobulate-procedure-result-matched-nodes
           (combobulate-procedure-apply procedure node))))

(defun combobulate-nix-test--normalized-buffer ()
  (string-trim (replace-regexp-in-string "[[:space:]\n]+" " " (buffer-string))))

(ert-deftest combobulate-nix-test-activation ()
  (combobulate-nix-test--with-buffer "{ first = 1; }"
    (should combobulate-nix-minor-mode)
    (should (eq (combobulate-primary-language) 'nix))
    (should (eq forward-sexp-function #'combobulate-forward-sexp-function))
    (should (eq transpose-sexps-function #'combobulate-transpose-sexp-function))))

(ert-deftest combobulate-nix-test-production-rules ()
  (combobulate-nix-test--with-buffer "{ first = 1; }"
    (should (member "apply_expression" (combobulate-production-rules-get "_expression")))
    (should (member "binding_set" (combobulate-production-rules-get-inverted "binding")))
    (should (member "formal" (combobulate-production-rules-get-inverted "identifier")))
    (should-not (seq-difference (combobulate-production-rules-get-types)
                                combobulate-rules-nix-types))))

(ert-deftest combobulate-nix-test-pretty-print-node-name ()
  (combobulate-nix-test--with-buffer
      "{ foo.bar = \"value\"; indented = ''text''; fallback = 1; }"
    (combobulate-nix-test--goto "foo.bar")
    (should (equal (combobulate-nix-pretty-print-node-name
                    (combobulate-nix-test--node '("binding")) "fallback")
                   "foo.bar"))
    (combobulate-nix-test--goto "\"value\"")
    (should (equal (combobulate-nix-pretty-print-node-name
                    (combobulate-nix-test--node '("string_expression")) "fallback")
                   "\"value\""))
    (combobulate-nix-test--goto "''text''")
    (should (equal (combobulate-nix-pretty-print-node-name
                    (combobulate-nix-test--node '("indented_string_expression")) "fallback")
                   "''text''"))
    (combobulate-nix-test--goto "1")
    (should (equal (combobulate-nix-pretty-print-node-name
                    (combobulate-nix-test--node) "fallback")
                   "fallback"))))

(ert-deftest combobulate-nix-test-edit-binding-values ()
  (combobulate-nix-test--with-buffer "{ first = 1; second = 2; }"
    (combobulate-nix-test--goto "1")
    (should (equal (combobulate-nix-test--matched-texts
                    (nth 0 (combobulate-read procedures-edit))
                    (combobulate-nix-test--node))
                   '("1" "2")))))

(ert-deftest combobulate-nix-test-edit-binding-attrpaths ()
  (combobulate-nix-test--with-buffer "{ first = 1; second = 2; }"
    (combobulate-nix-test--goto "first")
    (should (equal (combobulate-nix-test--matched-texts
                    (nth 1 (combobulate-read procedures-edit))
                    (combobulate-nix-test--node))
                   '("first" "second")))))

(ert-deftest combobulate-nix-test-navigate-bindings ()
  (combobulate-nix-test--with-buffer "{ first = 1; second = 2; }"
    (combobulate-nix-test--goto "first")
    (combobulate-navigate-next)
    (should (looking-at-p "second"))
    (combobulate-navigate-previous)
    (should (looking-at-p "first"))))

(ert-deftest combobulate-nix-test-navigate-binding-values ()
  (combobulate-nix-test--with-buffer "{ first = 1; second = 2; }"
    (combobulate-nix-test--goto "1")
    (combobulate-navigate-next)
    (should (looking-at-p "2"))
    (combobulate-navigate-previous)
    (should (looking-at-p "1"))))

(ert-deftest combobulate-nix-test-navigate-list-elements ()
  (combobulate-nix-test--with-buffer "[ 1 2 3 ]"
    (combobulate-nix-test--goto "1")
    (combobulate-navigate-next)
    (should (looking-at-p "2"))
    (combobulate-navigate-next)
    (should (looking-at-p "3"))
    (combobulate-navigate-previous 2)
    (should (looking-at-p "1"))))

(ert-deftest combobulate-nix-test-navigate-formals ()
  (combobulate-nix-test--with-buffer "{ first, second ? 2, ... }: first"
    (combobulate-nix-test--goto "first")
    (combobulate-navigate-next)
    (should (looking-at-p "second"))
    (combobulate-navigate-previous)
    (should (looking-at-p "first"))))

(ert-deftest combobulate-nix-test-navigate-inherit ()
  (combobulate-nix-test--with-buffer "{ inherit first second; third = 3; }"
    (combobulate-nix-test--goto "inherit")
    (combobulate-navigate-next)
    (should (looking-at-p "third"))
    (combobulate-navigate-previous)
    (should (looking-at-p "inherit"))))

(ert-deftest combobulate-nix-test-navigate-inherit-from ()
  (combobulate-nix-test--with-buffer "{ inherit (builtins) map; third = 3; }"
    (combobulate-nix-test--goto "inherit")
    (combobulate-navigate-next)
    (should (looking-at-p "third"))
    (combobulate-navigate-previous)
    (should (looking-at-p "inherit"))))

(ert-deftest combobulate-nix-test-navigate-hierarchy ()
  (combobulate-nix-test--with-buffer "{ first = { nested = 1; }; second = 2; }"
    (combobulate-nix-test--goto "first")
    (combobulate-navigate-down)
    (should (equal (combobulate-node-type (combobulate-nix-test--node))
                   "attrset_expression"))
    (combobulate-navigate-up)
    (should (looking-at-p "first"))))

(ert-deftest combobulate-nix-test-navigate-logical ()
  (combobulate-nix-test--with-buffer "{ first = 1; second = 2; }"
    (goto-char (point-min))
    (let ((start (point)))
      (combobulate-navigate-logical-next)
      (should (> (point) start))
      (combobulate-navigate-logical-previous)
      (should (= (point) start)))))

(ert-deftest combobulate-nix-test-navigate-binding-sexp ()
  (combobulate-nix-test--with-buffer "{ first = 1; second = 2; }"
    (combobulate-nix-test--goto "first")
    (let ((start (point))
          (end (combobulate-node-end (combobulate-nix-test--node '("binding")))))
      (forward-sexp)
      (should (= (point) end))
      (backward-sexp)
      (should (= (point) start)))))

(ert-deftest combobulate-nix-test-navigate-function-sexp ()
  (combobulate-nix-test--with-buffer "{ f = x: x + 1; }"
    (combobulate-nix-test--goto "x:")
    (let ((start (point))
          (end (combobulate-node-end (combobulate-nix-test--node '("function_expression")))))
      (forward-sexp)
      (should (= (point) end))
      (backward-sexp)
      (should (= (point) start)))))

(ert-deftest combobulate-nix-test-navigate-let-sexp ()
  (combobulate-nix-test--with-buffer "let first = 1; in first"
    (goto-char (point-min))
    (let ((start (point))
          (end (combobulate-node-end (combobulate-nix-test--node '("let_expression")))))
      (forward-sexp)
      (should (= (point) end))
      (backward-sexp)
      (should (= (point) start)))))

(ert-deftest combobulate-nix-test-navigate-defun ()
  (combobulate-nix-test--with-buffer "{ first = 1; second = 2; }"
    (combobulate-nix-test--goto "second")
    (forward-char 2)
    (let ((end (combobulate-node-end (combobulate-nix-test--node '("binding")))))
      (combobulate-navigate-beginning-of-defun)
      (should (looking-at-p "second"))
      (combobulate-navigate-end-of-defun)
      (should (= (point) end)))))

(ert-deftest combobulate-nix-test-mark-defun ()
  (combobulate-nix-test--with-buffer "{ first = 1; second = 2; }"
    (combobulate-nix-test--goto "second")
    (let ((node (combobulate-nix-test--node '("binding"))))
      (combobulate-mark-defun)
      (should mark-active)
      (should (= (region-beginning) (combobulate-node-start node)))
      (should (= (region-end) (combobulate-node-end node))))))

(ert-deftest combobulate-nix-test-kill-binding ()
  (combobulate-nix-test--with-buffer "{ first = 1; second = 2; third = 3; }"
    (combobulate-nix-test--goto "second")
    (combobulate-kill-node-dwim)
    (should (equal (combobulate-nix-test--normalized-buffer)
                   "{ first = 1; third = 3; }"))))

(ert-deftest combobulate-nix-test-drag-binding ()
  (combobulate-nix-test--with-buffer "{ first = 1; second = 2; third = 3; }"
    (combobulate-nix-test--goto "second")
    (combobulate-drag-down)
    (should (equal (combobulate-nix-test--normalized-buffer)
                   "{ first = 1; third = 3; second = 2; }"))
    (combobulate-drag-up)
    (should (equal (combobulate-nix-test--normalized-buffer)
                   "{ first = 1; second = 2; third = 3; }"))))
