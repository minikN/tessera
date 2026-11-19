;;; json-utils.el --- Tests for tessera-json-utils -*- lexical-binding: t -*-

(require 'ert)
(require 'tessera-json-utils)
(require 'json-ts-mode)
(require 'json5-ts-mode)

(setq treesit-auto-install-grammar 'never)
(transient-mark-mode 1)

;;; Helpers

(defconst tessera-json-utils-test--modes '(json-ts-mode json5-ts-mode)
  "Both modes; plain JSON is valid in each.")

(defun tessera-json-utils-test--call (mode text fn)
  "Call FN in a MODE buffer holding TEXT, with point at its ‸, which is removed."
  (with-temp-buffer
    (funcall mode)
    (insert text)
    (goto-char (point-min))
    (search-forward "‸")
    (delete-char -1)
    (ert-info ((format "%s: %S" mode text))
      (funcall fn))))

(defun tessera-json-utils-test--check (modes text command expected)
  "In each of MODES, run COMMAND on TEXT and compare the buffer with EXPECTED."
  (dolist (mode (ensure-list modes))
    (tessera-json-utils-test--call
     mode text
     (lambda ()
       (call-interactively command)
       (should (equal (buffer-string) expected))))))

(defun tessera-json-utils-test--user-error (modes text command message)
  "In each of MODES, check that COMMAND on TEXT signals a user error MESSAGE.
The buffer must stay unchanged."
  (dolist (mode (ensure-list modes))
    (tessera-json-utils-test--call
     mode text
     (lambda ()
       (should (equal (cadr (should-error (call-interactively command)
                                          :type 'user-error))
                      message))
       (should (equal (buffer-string) (string-replace "‸" "" text)))))))

(defmacro tessera-json-utils-test--with-kill-ring (&rest body)
  "Run BODY with an empty kill ring of its own."
  `(let ((kill-ring nil)
         (kill-ring-yank-pointer nil)
         (last-command nil)
         (interprogram-cut-function nil)
         (interprogram-paste-function nil))
     ,@body))

(defun tessera-json-utils-test--kill (modes text expected killed)
  "In each of MODES, kill at point in TEXT.
Compare the buffer with EXPECTED and the kill ring with KILLED."
  (dolist (mode (ensure-list modes))
    (tessera-json-utils-test--call
     mode text
     (lambda ()
       (tessera-json-utils-test--with-kill-ring
        (call-interactively #'tessera-json-utils-kill)
        (should (equal (buffer-string) expected))
        (should (equal kill-ring (list killed))))))))

(defun tessera-json-utils-test--path (modes text path)
  "In each of MODES, check that the jq path at point in TEXT is PATH.
It must be shown and copied."
  (dolist (mode (ensure-list modes))
    (tessera-json-utils-test--call
     mode text
     (lambda ()
       (tessera-json-utils-test--with-kill-ring
        (let ((inhibit-message t))
          (with-current-buffer (messages-buffer)
            (let ((inhibit-read-only t))
              (erase-buffer)))
          (call-interactively #'tessera-json-utils-print-path)
          (should (equal kill-ring (list path)))
          (should (equal (with-current-buffer (messages-buffer) (buffer-string))
                         (concat path "\n")))))))))

;;; Expand and contract

(ert-deftest tessera-json-utils-test-expand-object ()
  (tessera-json-utils-test--check
   tessera-json-utils-test--modes
   "{\"a\": 1, ‸\"b\": [1, 2]}"
   #'tessera-json-utils-expand-node
   "{
  \"a\": 1,
  \"b\": [1, 2]
}"))

(ert-deftest tessera-json-utils-test-expand-nested-array ()
  (tessera-json-utils-test--check
   tessera-json-utils-test--modes
   "{\"a\": 1, \"b\": [1, ‸2]}"
   #'tessera-json-utils-expand-node
   "{\"a\": 1, \"b\": [
  1,
  2
]}"))

(ert-deftest tessera-json-utils-test-expand-before-point ()
  ;; Point right after a list means that list
  (tessera-json-utils-test--check
   tessera-json-utils-test--modes
   "{\"a\": [1, 2]‸, \"b\": 3}"
   #'tessera-json-utils-expand-node
   "{\"a\": [
  1,
  2
], \"b\": 3}"))

(ert-deftest tessera-json-utils-test-expand-trailing-comma ()
  ;; JSON parses `,}' as an ERROR node and `,]' as a MISSING element.
  (tessera-json-utils-test--check
   tessera-json-utils-test--modes
   "{\"a\": 1, ‸\"b\": 2,}"
   #'tessera-json-utils-expand-node
   "{
  \"a\": 1,
  \"b\": 2,
}")
  (tessera-json-utils-test--check
   tessera-json-utils-test--modes
   "{\"a\": 1, ‸\"b\": 2 ,\n}"
   #'tessera-json-utils-expand-node
   "{
  \"a\": 1,
  \"b\": 2,
}")
  (tessera-json-utils-test--check
   tessera-json-utils-test--modes
   "[1, ‸2,]"
   #'tessera-json-utils-expand-node
   "[
  1,
  2,
]")
  (tessera-json-utils-test--check
   tessera-json-utils-test--modes
   "[1, ‸2 , ]"
   #'tessera-json-utils-expand-node
   "[
  1,
  2,
]"))

(ert-deftest tessera-json-utils-test-contract-object ()
  (tessera-json-utils-test--check
   tessera-json-utils-test--modes
   "{
  \"a\": 1,
  ‸\"b\": [1, 2]
}"
   #'tessera-json-utils-contract-node
   "{ \"a\": 1, \"b\": [1, 2] }"))

(ert-deftest tessera-json-utils-test-contract-array ()
  (tessera-json-utils-test--check
   tessera-json-utils-test--modes
   "[
  1,
  ‸2
]"
   #'tessera-json-utils-contract-node
   "[1, 2]"))

(ert-deftest tessera-json-utils-test-contract-nested ()
  (tessera-json-utils-test--check
   tessera-json-utils-test--modes
   "{
  \"a\": [
    1,
    ‸2
  ],
  \"b\": 3
}"
   #'tessera-json-utils-contract-node
   "{
  \"a\": [1, 2],
  \"b\": 3
}"))

(ert-deftest tessera-json-utils-test-contract-trailing-comma ()
  (tessera-json-utils-test--check
   tessera-json-utils-test--modes
   "{
  \"a\": 1,
  ‸\"b\": 2,
}"
   #'tessera-json-utils-contract-node
   "{ \"a\": 1, \"b\": 2 }")
  (tessera-json-utils-test--check
   tessera-json-utils-test--modes
   "[
  1,
  ‸2,
]"
   #'tessera-json-utils-contract-node
   "[1, 2]"))

(ert-deftest tessera-json-utils-test-expand-contract-json5 ()
  (tessera-json-utils-test--check
   'json5-ts-mode
   "{a: 1, ‸'b': [1, 2], c: 3,}"
   #'tessera-json-utils-expand-node
   "{
  a: 1,
  'b': [1, 2],
  c: 3,
}")
  (tessera-json-utils-test--check
   'json5-ts-mode
   "{
  a: 1,
  ‸'b': [1, 2],
  c: 3,
}"
   #'tessera-json-utils-contract-node
   "{ a: 1, 'b': [1, 2], c: 3 }"))

(ert-deftest tessera-json-utils-test-expand-contract-comments ()
  (dolist (command '(tessera-json-utils-expand-node tessera-json-utils-contract-node))
    (tessera-json-utils-test--user-error
     tessera-json-utils-test--modes
     "{
  \"a\": 1, // one
  ‸\"b\": 2
}"
     command
     "The object or array has comments")
    (tessera-json-utils-test--user-error
     tessera-json-utils-test--modes
     "[1, /* one */ ‸2]"
     command
     "The object or array has comments")))

(ert-deftest tessera-json-utils-test-expand-contract-empty ()
  (dolist (command '(tessera-json-utils-expand-node tessera-json-utils-contract-node))
    (dolist (text '("{‸}" "[‸]" "{\n  ‸\n}"))
      (tessera-json-utils-test--user-error
       tessera-json-utils-test--modes text command
       "The object or array is empty"))))

(ert-deftest tessera-json-utils-test-expand-contract-syntax-errors ()
  (dolist (command '(tessera-json-utils-expand-node tessera-json-utils-contract-node))
    (tessera-json-utils-test--user-error
     tessera-json-utils-test--modes "[1, ‸2 3]" command
     "The object or array has syntax errors")
    (tessera-json-utils-test--user-error
     tessera-json-utils-test--modes "{\"a\": 1 ‸\"b\": 2}" command
     "The object or array has syntax errors")
    (tessera-json-utils-test--user-error
     'json-ts-mode "{\"a\": 1, ‸\"b\" 2}" command
     "The object or array has syntax errors")))

(ert-deftest tessera-json-utils-test-expand-contract-no-list ()
  (dolist (command '(tessera-json-utils-expand-node tessera-json-utils-contract-node))
    (tessera-json-utils-test--user-error
     tessera-json-utils-test--modes "‸\"a\"" command
     "No object or array at point")))

;;; Sort

(ert-deftest tessera-json-utils-test-sort-object ()
  (tessera-json-utils-test--check
   tessera-json-utils-test--modes
   "{\"c\": 1, ‸\"a\": 2, \"b\": 3}"
   #'tessera-json-utils-sort
   "{\"a\": 2, \"b\": 3, \"c\": 1}"))

(ert-deftest tessera-json-utils-test-sort-only-object-at-point ()
  (tessera-json-utils-test--check
   tessera-json-utils-test--modes
   "{\"c\": 1, \"a\": {\"z\": 1, ‸\"y\": 2}, \"b\": 3}"
   #'tessera-json-utils-sort
   "{\"c\": 1, \"a\": {\"y\": 2, \"z\": 1}, \"b\": 3}")
  (tessera-json-utils-test--check
   tessera-json-utils-test--modes
   "{\"c\": 1, ‸\"a\": {\"z\": 1, \"y\": 2}, \"b\": 3}"
   #'tessera-json-utils-sort
   "{\"a\": {\"z\": 1, \"y\": 2}, \"b\": 3, \"c\": 1}")
  ;; Inside an array inside an object, the object is sorted.
  (tessera-json-utils-test--check
   tessera-json-utils-test--modes
   "{\"c\": [3, ‸1], \"a\": 2}"
   #'tessera-json-utils-sort
   "{\"a\": 2, \"c\": [3, 1]}"))

(ert-deftest tessera-json-utils-test-sort-keeps-layout ()
  (tessera-json-utils-test--check
   tessera-json-utils-test--modes
   "{ \"b\": 1, ‸\"a\": 2,
  \"c\": 3 }"
   #'tessera-json-utils-sort
   "{ \"a\": 2, \"b\": 1,
  \"c\": 3 }"))

(ert-deftest tessera-json-utils-test-sort-multi-line-value ()
  (tessera-json-utils-test--check
   tessera-json-utils-test--modes
   "{
  \"c\": [
    1,
    2
  ],
  ‸\"a\": 1,
  \"b\": {
    \"x\": 1
  }
}"
   #'tessera-json-utils-sort
   "{
  \"a\": 1,
  \"b\": {
    \"x\": 1
  },
  \"c\": [
    1,
    2
  ]
}"))

(ert-deftest tessera-json-utils-test-sort-trailing-comma ()
  (tessera-json-utils-test--check
   tessera-json-utils-test--modes
   "{
  \"c\": 1,
  ‸\"b\": 2,
}"
   #'tessera-json-utils-sort
   "{
  \"b\": 2,
  \"c\": 1,
}"))

(ert-deftest tessera-json-utils-test-sort-json5-keys ()
  ;; Keys compare unquoted, whatever their quotes.
  (tessera-json-utils-test--check
   'json5-ts-mode
   "{c: 1, 'b': 2, ‸\"a\": 3,}"
   #'tessera-json-utils-sort
   "{\"a\": 3, 'b': 2, c: 1,}"))

(ert-deftest tessera-json-utils-test-sort-comments ()
  (tessera-json-utils-test--user-error
   tessera-json-utils-test--modes
   "{
  \"c\": 1, // one
  ‸\"b\": 2
}"
   #'tessera-json-utils-sort
   "The object has comments"))

(ert-deftest tessera-json-utils-test-sort-array ()
  (tessera-json-utils-test--user-error
   tessera-json-utils-test--modes "[3, ‸1, 2]" #'tessera-json-utils-sort
   "No object at point"))

;;; Kill

(ert-deftest tessera-json-utils-test-kill-array ()
  (tessera-json-utils-test--kill
   tessera-json-utils-test--modes
   "{\"a\": [1, ‸2, 3], \"b\": 1}"
   "{\"a\": [1, ], \"b\": 1}"
   "2, 3"))

(ert-deftest tessera-json-utils-test-kill-object ()
  (tessera-json-utils-test--kill
   tessera-json-utils-test--modes
   "{\"a\": 1, ‸\"b\": 2}\n"
   "{\"a\": 1, }\n"
   "\"b\": 2")
  (tessera-json-utils-test--kill
   tessera-json-utils-test--modes
   "{\"a\": [1, 2]‸, \"b\": 1}"
   "{\"a\": [1, 2]}"
   ", \"b\": 1")
  (tessera-json-utils-test--kill
   'json5-ts-mode
   "{a: 1, ‸b: 2}"
   "{a: 1, }"
   "b: 2"))

(ert-deftest tessera-json-utils-test-kill-string ()
  (tessera-json-utils-test--kill
   tessera-json-utils-test--modes
   "{\"a\": \"he‸llo world\", \"b\": 2}"
   "{\"a\": \"he\", \"b\": 2}"
   "llo world")
  (tessera-json-utils-test--kill
   'json5-ts-mode
   "{a: 'he‸llo world', b: 2}"
   "{a: 'he', b: 2}"
   "llo world"))

(ert-deftest tessera-json-utils-test-kill-line-fallback ()
  ;; The object ends on a later line.
  (tessera-json-utils-test--kill
   tessera-json-utils-test--modes
   "{
  \"a\": ‸1,
  \"b\": 2
}"
   "{\n  \"a\": \n  \"b\": 2\n}"
   "1,")
  ;; Not inside an object, array or string.
  (tessera-json-utils-test--kill
   tessera-json-utils-test--modes
   "‸[1, 2]\n"
   "\n"
   "[1, 2]"))

;;; jq path

(ert-deftest tessera-json-utils-test-path-nested ()
  (tessera-json-utils-test--path
   tessera-json-utils-test--modes
   "{\"a\": [1, {\"b-c\": ‸2}]}"
   ".a[1][\"b-c\"]")
  (tessera-json-utils-test--path
   tessera-json-utils-test--modes
   "{\"a\": [1, {\"b-c\": 2‸}]}"
   ".a[1][\"b-c\"]")
  (tessera-json-utils-test--path
   tessera-json-utils-test--modes
   "{\"a\": [1, ‸{\"b-c\": 2}]}"
   ".a[1]"))

(ert-deftest tessera-json-utils-test-path-key ()
  (tessera-json-utils-test--path
   tessera-json-utils-test--modes
   "{\"a\": [1, {\"b-‸c\": 2}]}"
   ".a[1][\"b-c\"]")
  (tessera-json-utils-test--path
   tessera-json-utils-test--modes
   "{\"a\": [1, {‸\"b-c\": 2}]}"
   ".a[1][\"b-c\"]"))

(ert-deftest tessera-json-utils-test-path-array-comments ()
  (tessera-json-utils-test--path
   tessera-json-utils-test--modes
   "{\"a\": [
  // zero
  1, // one
  /* two */
  ‸2
]}"
   ".a[1]"))

(ert-deftest tessera-json-utils-test-path-root-array ()
  (tessera-json-utils-test--path
   tessera-json-utils-test--modes
   "[1, {\"x\": ‸2}]"
   ".[1].x")
  (tessera-json-utils-test--path
   tessera-json-utils-test--modes
   "[1, 2‸]"
   ".[1]"))

(ert-deftest tessera-json-utils-test-path-json5-identifiers ()
  (tessera-json-utils-test--path
   'json5-ts-mode "{foo_bar: {baz: ‸1}}" ".foo_bar.baz")
  (tessera-json-utils-test--path
   'json5-ts-mode "{foo: {$bar: ‸1}}" ".foo[\"$bar\"]")
  (tessera-json-utils-test--path
   'json5-ts-mode "{foo: {'b-c': ‸1}}" ".foo[\"b-c\"]"))

(ert-deftest tessera-json-utils-test-path-punctuation ()
  ;; On a bracket, the list; right after a value, that value
  (tessera-json-utils-test--path
   tessera-json-utils-test--modes "{\"a\": ‸[1, 2]}" ".a")
  (tessera-json-utils-test--path
   tessera-json-utils-test--modes "[[1]‸, 2]" ".[0]")
  (tessera-json-utils-test--path
   tessera-json-utils-test--modes "{\"a\": [1, {\"b-c\": 2}‸]}" ".a[1]")
  (tessera-json-utils-test--path
   tessera-json-utils-test--modes "{\"a\": {\"b\": 1}‸, \"c\": 2}" ".a")
  (tessera-json-utils-test--path
   tessera-json-utils-test--modes "{\"a\": \"x\"‸, \"c\": 2}" ".a")
  (tessera-json-utils-test--path
   tessera-json-utils-test--modes "{\"a\": [1, /* c‸ */ 2]}" ".a"))

(ert-deftest tessera-json-utils-test-path-escaped-keys ()
  (tessera-json-utils-test--path
   tessera-json-utils-test--modes "{\"a\\\"b\": ‸1}" ".[\"a\\\"b\"]")
  (tessera-json-utils-test--path
   tessera-json-utils-test--modes "{\"a\\nb\": ‸1}" ".[\"a\\nb\"]")
  (tessera-json-utils-test--path
   'json5-ts-mode "{'a\\'b\"c': ‸1}" ".[\"a'b\\\"c\"]"))

(ert-deftest tessera-json-utils-test-path-outside ()
  (dolist (text '("‸1" "‸{\"a\": 1}" "{\"a\": 1}‸" "‸[1, 2]" "[1, 2]‸"))
    (tessera-json-utils-test--user-error
     tessera-json-utils-test--modes text #'tessera-json-utils-print-path
     "Not inside an object or array")))

;;; Keymap

(ert-deftest tessera-json-utils-test-keymap ()
  (pcase-dolist (`(,key . ,command)
                 '(("x" . tessera-json-utils-expand-node)
                   ("c" . tessera-json-utils-contract-node)
                   ("k" . tessera-json-utils-kill)
                   ("j" . tessera-json-utils-print-path)
                   ("s" . tessera-json-utils-sort)))
    (should (commandp command))
    (should (eq (keymap-lookup tessera-json-utils-map key) command))))

;;; json-utils.el ends here
