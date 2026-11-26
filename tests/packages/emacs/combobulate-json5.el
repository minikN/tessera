;;; combobulate-json5.el --- JSON5 Combobulate tests  -*- lexical-binding: t; -*-

(require 'tessera-combobulate-json5)
(require 'json5-ts-mode)

(setq treesit-auto-install-grammar 'never)

(defmacro combobulate-json5-test--with-buffer (text &rest body)
  (declare (indent 1))
  `(with-temp-buffer
     (insert ,text)
     (json5-ts-mode)
     (combobulate-mode 1)
     (transient-mark-mode 1)
     (let ((combobulate-flash-node nil))
       ,@body)))

(defun combobulate-json5-test--goto (text)
  (goto-char (point-min))
  (search-forward text)
  (goto-char (match-beginning 0)))

(defun combobulate-json5-test--node (&optional types)
  (combobulate-node-at-point types))

(defun combobulate-json5-test--matched-texts (procedure node)
  (mapcar #'combobulate-node-text
          (combobulate-procedure-result-matched-nodes
           (combobulate-procedure-apply procedure node))))

(defun combobulate-json5-test--normalized-buffer ()
  (string-trim (replace-regexp-in-string "[[:space:]\n]+" " " (buffer-string))))

(ert-deftest combobulate-json5-test-activation ()
  (combobulate-json5-test--with-buffer "{first: 1}"
    (should combobulate-json5-minor-mode)
    (should (eq (combobulate-primary-language) 'json5))
    (should (eq forward-sexp-function #'combobulate-forward-sexp-function))
    (should (eq transpose-sexps-function #'combobulate-transpose-sexp-function))))

(ert-deftest combobulate-json5-test-pretty-print-node-name ()
  (combobulate-json5-test--with-buffer
      "{first: 1, \"second\": \"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ\"}"
    (combobulate-json5-test--goto "first")
    (should (equal (tessera-combobulate-json5-pretty-print-node-name
                    (combobulate-json5-test--node '("member")) "fallback")
                   "first"))
    (combobulate-json5-test--goto "\"second\"")
    (should (equal (tessera-combobulate-json5-pretty-print-node-name
                    (combobulate-json5-test--node '("member")) "fallback")
                   "\"second\""))
    (combobulate-json5-test--goto "abcdefghijklmnopqrstuvwxyz")
    (let* ((node (combobulate-json5-test--node '("string")))
           (text (combobulate-node-text node)))
      (should (equal (tessera-combobulate-json5-pretty-print-node-name node "fallback")
                     (concat (substring text 0 40) " … "))))
    (combobulate-json5-test--goto "1")
    (should (equal (tessera-combobulate-json5-pretty-print-node-name
                    (combobulate-json5-test--node) "fallback")
                   "fallback"))))

(ert-deftest combobulate-json5-test-edit-member-values ()
  (combobulate-json5-test--with-buffer "{first: 1, second: 2}"
    (combobulate-json5-test--goto "1")
    (should (equal (combobulate-json5-test--matched-texts
                    (nth 0 (combobulate-read procedures-edit))
                    (combobulate-json5-test--node))
                   '("1" "2")))))

(ert-deftest combobulate-json5-test-edit-member-names ()
  (combobulate-json5-test--with-buffer "{first: 1, second: 2}"
    (combobulate-json5-test--goto "first")
    (should (equal (combobulate-json5-test--matched-texts
                    (nth 1 (combobulate-read procedures-edit))
                    (combobulate-json5-test--node))
                   '("first" "second")))))

(ert-deftest combobulate-json5-test-navigate-members ()
  (combobulate-json5-test--with-buffer "{first: 1, second: 2}"
    (combobulate-json5-test--goto "first")
    (combobulate-navigate-next)
    (should (looking-at-p "second"))
    (combobulate-navigate-previous)
    (should (looking-at-p "first"))))

(ert-deftest combobulate-json5-test-navigate-member-values ()
  (combobulate-json5-test--with-buffer "{first: 1, second: 2}"
    (combobulate-json5-test--goto "1")
    (combobulate-navigate-next)
    (should (looking-at-p "2"))
    (combobulate-navigate-previous)
    (should (looking-at-p "1"))))

(ert-deftest combobulate-json5-test-navigate-array-elements ()
  (combobulate-json5-test--with-buffer "[1, 2, 3]"
    (combobulate-json5-test--goto "1")
    (combobulate-navigate-next)
    (should (looking-at-p "2"))
    (combobulate-navigate-next)
    (should (looking-at-p "3"))
    (combobulate-navigate-previous 2)
    (should (looking-at-p "1"))))

(ert-deftest combobulate-json5-test-navigate-hierarchy ()
  (combobulate-json5-test--with-buffer "{first: {nested: 1}, second: 2}"
    (combobulate-json5-test--goto "first")
    (combobulate-navigate-down)
    (should (looking-at-p "{"))
    (combobulate-navigate-up)
    (should (looking-at-p "first"))))

(ert-deftest combobulate-json5-test-navigate-logical ()
  (combobulate-json5-test--with-buffer "{first: 1, second: 2}"
    (goto-char (point-min))
    (let ((start (point)))
      (combobulate-navigate-logical-next)
      (should (> (point) start))
      (combobulate-navigate-logical-previous)
      (should (= (point) start)))))

(ert-deftest combobulate-json5-test-navigate-sexp ()
  (combobulate-json5-test--with-buffer "{first: 1, second: 2}"
    (combobulate-json5-test--goto "first")
    (let ((start (point))
          (end (combobulate-node-end (combobulate-json5-test--node '("member")))))
      (forward-sexp)
      (should (= (point) end))
      (backward-sexp)
      (should (= (point) start)))))

(ert-deftest combobulate-json5-test-navigate-defun ()
  (combobulate-json5-test--with-buffer "{first: 1, second: 2}"
    (combobulate-json5-test--goto "second")
    (combobulate-navigate-beginning-of-defun)
    (should (= (point) (point-min)))
    (combobulate-navigate-end-of-defun)
    (should (= (point) (point-max)))))

(ert-deftest combobulate-json5-test-mark-defun ()
  (combobulate-json5-test--with-buffer "{first: 1, second: 2}"
    (combobulate-json5-test--goto "second")
    (combobulate-mark-defun)
    (should mark-active)
    (should (= (region-beginning) (point-min)))
    (should (= (region-end) (point-max)))))

(ert-deftest combobulate-json5-test-envelope-array ()
  (combobulate-json5-test--with-buffer "{first: 1}"
    (should (eq (lookup-key combobulate-json5-envelope-map "a")
                'combobulate-json5-envelope-nest-array))
    (combobulate-json5-test--goto "1")
    (combobulate-execute-envelope
     "nest-array" (combobulate-json5-test--node '("number")))
    (should (equal (buffer-string) "{first: [1]}"))))

(ert-deftest combobulate-json5-test-envelope-member-object ()
  (combobulate-json5-test--with-buffer "{first: 1}"
    (should (eq (lookup-key combobulate-json5-envelope-map "o")
                'combobulate-json5-envelope-nest-member-object))
    (combobulate-json5-test--goto "first")
    (cl-letf (((symbol-function 'combobulate-envelope-prompt)
               (lambda (_prompt _default &optional _buffer update-fn &rest _)
                 (when update-fn (funcall update-fn))
                 "outer")))
      (combobulate-execute-envelope
       "nest-member-object" (combobulate-json5-test--node '("member"))))
    (should (equal (combobulate-json5-test--normalized-buffer)
                   "{\"outer\": { first: 1 }}"))))

(ert-deftest combobulate-json5-test-kill-member ()
  (combobulate-json5-test--with-buffer "{first: 1, second: 2, third: 3}"
    (combobulate-json5-test--goto "second")
    (combobulate-kill-node-dwim)
    (should (equal (combobulate-json5-test--normalized-buffer)
                   "{first: 1, third: 3}"))))

(ert-deftest combobulate-json5-test-drag-member ()
  (combobulate-json5-test--with-buffer "{first: 1, second: 2, third: 3}"
    (combobulate-json5-test--goto "second")
    (combobulate-drag-down)
    (should (equal (buffer-string) "{first: 1, third: 3, second: 2}"))
    (combobulate-drag-up)
    (should (equal (buffer-string) "{first: 1, second: 2, third: 3}"))))
