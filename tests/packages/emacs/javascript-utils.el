;;; javascript-utils.el --- Tests for tessera-javascript-utils -*- lexical-binding: t -*-

;;; Commentary:

;; Refactorings are run in `js-ts-mode' and `typescript-ts-mode' buffers
;; and the whole buffer is compared with the expected text.  In both, `‸'
;; marks point; in the input, a second `‸' marks the other end of the
;; active region.  An expected text without `‸' leaves point unchecked.
;;
;; Package commands are run against temporary packages, and for real with
;; each tool, which must work with no Node.js, bun or deno on `PATH'.

;;; Code:

(require 'ert)
(require 'js)
(require 'typescript-ts-mode)
(require 'tessera-javascript-utils)

(setq treesit-auto-install-grammar 'never
      js-indent-level 2
      typescript-ts-mode-indent-offset 2)
(transient-mark-mode 1)

;;;; Helpers

(defun tessera-javascript-utils-test--run (mode text command &rest args)
  "Run COMMAND in a MODE buffer with TEXT and return the buffer's text.
In TEXT, `‸' marks point and a second `‸' the other end of the active
region.  COMMAND is called interactively, or with ARGS if there are any.
The text returned has `‸' at point."
  (with-temp-buffer
    (insert text)
    (goto-char (point-min))
    (let (marks)
      (while (search-forward "‸" nil t)
        (replace-match "")
        (push (point) marks))
      (setq marks (nreverse marks))
      (funcall mode)
      (goto-char (or (car marks) (point-min)))
      (when (cadr marks)
        (push-mark (cadr marks) t t))
      (if args
          (apply command args)
        (call-interactively command))
      (insert "‸")
      (buffer-string))))

(defun tessera-javascript-utils-test--check (mode before command after &rest args)
  "Check that COMMAND turns BEFORE into AFTER in a MODE buffer.
Point is only checked if AFTER has a `‸'.  ARGS are passed to COMMAND."
  (let ((result (apply #'tessera-javascript-utils-test--run mode before command args)))
    (should (equal (if (string-search "‸" after)
                       result
                     (string-replace "‸" "" result))
                   after))))

(defmacro tessera-javascript-utils-test--with-kill-ring (&rest body)
  "Run BODY with an empty kill ring of its own."
  (declare (indent 0))
  `(let ((kill-ring nil)
         (kill-ring-yank-pointer nil)
         (interprogram-cut-function nil)
         (interprogram-paste-function nil))
     ,@body))

(defun tessera-javascript-utils-test--make-package (files)
  "Return a new temporary directory holding FILES.
FILES is an alist of (NAME . CONTENT), where NAME may have directories."
  (let ((dir (file-name-as-directory (make-temp-file "tessera-javascript-utils-" t))))
    (pcase-dolist (`(,name . ,content) files)
      (let ((file (expand-file-name name dir)))
        (make-directory (file-name-directory file) t)
        (with-temp-file file (insert content))))
    dir))

(defmacro tessera-javascript-utils-test--with-package (dir files &rest body)
  "Run BODY with DIR bound to a temporary directory holding FILES.
See `tessera-javascript-utils-test--make-package' for FILES."
  (declare (indent 2))
  `(let ((,dir (tessera-javascript-utils-test--make-package ,files)))
     (unwind-protect
         (progn ,@body)
       (delete-directory ,dir t))))

(defmacro tessera-javascript-utils-test--with-loop-guard (&rest body)
  "Run BODY, failing once it has called `syntax-ppss' 1000 times.
This turns an endless loop of the JSONC reader into a test failure."
  (declare (indent 0))
  (let ((calls (make-symbol "calls"))
        (guard (make-symbol "guard")))
    `(let* ((,calls 0)
            (,guard (lambda (&rest _)
                      (when (> (setq ,calls (1+ ,calls)) 1000)
                        (error "Endless loop: `syntax-ppss' called %d times" ,calls)))))
       (advice-add 'syntax-ppss :before ,guard)
       (unwind-protect
           (progn ,@body)
         (advice-remove 'syntax-ppss ,guard)))))

(defun tessera-javascript-utils-test--strip (command)
  "Return COMMAND without the store directories of its programs."
  (replace-regexp-in-string "/nix/store/[^/ ]+/bin/" "" command))

;;;; Ternary to if

(ert-deftest tessera-javascript-utils-test-ternary-return ()
  (tessera-javascript-utils-test--check
   #'js-ts-mode
   "function f(a) {
  return a ? ‸1 : 2;
}
"
   #'tessera-javascript-utils-ternary-to-if
   "function f(a) {
  if (a) {
    return 1;
  } else {
    return 2;
  }
}
"))

(ert-deftest tessera-javascript-utils-test-ternary-augmented-assignment ()
  (tessera-javascript-utils-test--check
   #'js-ts-mode
   "x += ‸a ? 1 : 2;
"
   #'tessera-javascript-utils-ternary-to-if
   "if (a) {
  x += 1;
} else {
  x += 2;
}
"))

(ert-deftest tessera-javascript-utils-test-ternary-typed-declaration ()
  (tessera-javascript-utils-test--check
   #'typescript-ts-mode
   "const v: number = (‸a ? 1 : 2);
"
   #'tessera-javascript-utils-ternary-to-if
   "let v: number;
if (a) {
  v = 1;
} else {
  v = 2;
}
"))

(ert-deftest tessera-javascript-utils-test-ternary-argument ()
  (should-error
   (tessera-javascript-utils-test--run
    #'js-ts-mode "foo(‸a ? 1 : 2);\n" #'tessera-javascript-utils-ternary-to-if)
   :type 'user-error))

;;;; Log and debug

(ert-deftest tessera-javascript-utils-test-log-object ()
  (tessera-javascript-utils-test--check
   #'js-ts-mode
   "const x = ‸foo.bar;
"
   #'tessera-javascript-utils-log-this
   "const x = foo.bar;
console.log(\"foo = \", foo);
"))

(ert-deftest tessera-javascript-utils-test-log-member ()
  (tessera-javascript-utils-test--check
   #'js-ts-mode
   "const x = foo.‸bar;
"
   #'tessera-javascript-utils-log-this
   "const x = foo.bar;
console.log(\"foo.bar = \", foo.bar);
"))

(ert-deftest tessera-javascript-utils-test-log-after-expression ()
  ;; Point right after an expression means that expression, not the
  ;; punctuation after it.
  (tessera-javascript-utils-test--check
   #'js-ts-mode
   "const x = foo.bar‸;
"
   #'tessera-javascript-utils-log-this
   "const x = foo.bar;
console.log(\"foo.bar = \", foo.bar);
"))

(ert-deftest tessera-javascript-utils-test-log-before-return ()
  (tessera-javascript-utils-test--check
   #'js-ts-mode
   "function f(a) {
  return ‸a;
}
"
   #'tessera-javascript-utils-log-this
   "function f(a) {
  console.log(\"a = \", a);
  return a;
}
"))

(ert-deftest tessera-javascript-utils-test-log-parameter ()
  (tessera-javascript-utils-test--check
   #'typescript-ts-mode
   "function f(‸a: number) {
  return a;
}
"
   #'tessera-javascript-utils-log-this
   "function f(a: number) {
  console.log(\"a = \", a);
  return a;
}
"))

(ert-deftest tessera-javascript-utils-test-log-region ()
  (tessera-javascript-utils-test--check
   #'js-ts-mode
   "const z = ‸\"x\" + y‸;
"
   #'tessera-javascript-utils-log-this
   "const z = \"x\" + y;
console.log(\"\\\"x\\\" + y = \", \"x\" + y);
"))

(ert-deftest tessera-javascript-utils-test-debug ()
  (tessera-javascript-utils-test--check
   #'js-ts-mode
   "const y = ‸x;
"
   #'tessera-javascript-utils-debug-this
   "const y = x;
debug(\"x = %s\", x);
"))

;;;; Strings and declarations

(ert-deftest tessera-javascript-utils-test-split-string ()
  (tessera-javascript-utils-test--check
   #'js-ts-mode
   "const s = \"foo‸bar\";
"
   #'tessera-javascript-utils-split-string
   "const s = \"foo\" + \"‸bar\";
"))

(ert-deftest tessera-javascript-utils-test-split-string-single-quotes ()
  (tessera-javascript-utils-test--check
   #'typescript-ts-mode
   "const s = 'foo‸bar';
"
   #'tessera-javascript-utils-split-string
   "const s = 'foo' + '‸bar';
"))

(ert-deftest tessera-javascript-utils-test-join-string ()
  (tessera-javascript-utils-test--check
   #'js-ts-mode
   "const s = \"foo\" + \"‸bar\";
"
   #'tessera-javascript-utils-split-string
   "const s = \"foo‸bar\";
"))

(ert-deftest tessera-javascript-utils-test-join-string-before-joint ()
  (tessera-javascript-utils-test--check
   #'js-ts-mode
   "const s = \"foo‸\" + \"bar\";
"
   #'tessera-javascript-utils-split-string
   "const s = \"foo‸bar\";
"))

(ert-deftest tessera-javascript-utils-test-split-declaration ()
  (tessera-javascript-utils-test--check
   #'js-ts-mode
   "let a = 1, ‸b = 2;
"
   #'tessera-javascript-utils-split-declaration
   "let a = 1;
let b = 2;
"))

(ert-deftest tessera-javascript-utils-test-split-export-declaration ()
  (tessera-javascript-utils-test--check
   #'typescript-ts-mode
   "export const ‸a = 1, b: string = \"b\";
"
   #'tessera-javascript-utils-split-declaration
   "export const a = 1;
export const b: string = \"b\";
"))

;;;; Expand and contract

(ert-deftest tessera-javascript-utils-test-expand-object ()
  (tessera-javascript-utils-test--check
   #'js-ts-mode
   "const o = {a: 1, ‸b: 2};
"
   #'tessera-javascript-utils-expand-node
   "const o = {
  a: 1,
  b: 2
};
"))

(ert-deftest tessera-javascript-utils-test-expand-arguments ()
  (tessera-javascript-utils-test--check
   #'js-ts-mode
   "foo(a, ‸b);
"
   #'tessera-javascript-utils-expand-node
   "foo(
  a,
  b
);
"))

(ert-deftest tessera-javascript-utils-test-contract-object ()
  (tessera-javascript-utils-test--check
   #'js-ts-mode
   "const o = {
  a: 1,
  ‸b: 2,
};
"
   #'tessera-javascript-utils-contract-node
   "const o = { a: 1, b: 2 };
"))

(ert-deftest tessera-javascript-utils-test-contract-array ()
  (tessera-javascript-utils-test--check
   #'typescript-ts-mode
   "const a = [
  1,
  ‸2
];
"
   #'tessera-javascript-utils-contract-node
   "const a = [1, 2];
"))

;;;; Async

(ert-deftest tessera-javascript-utils-test-async-function ()
  (tessera-javascript-utils-test--check
   #'js-ts-mode
   "function ‸f() {}
"
   #'tessera-javascript-utils-toggle-async
   "async function f() {}
"))

(ert-deftest tessera-javascript-utils-test-async-function-off ()
  (tessera-javascript-utils-test--check
   #'js-ts-mode
   "async function f() {
  return ‸1;
}
"
   #'tessera-javascript-utils-toggle-async
   "function f() {
  return 1;
}
"))

(ert-deftest tessera-javascript-utils-test-async-typed-arrow ()
  (tessera-javascript-utils-test--check
   #'typescript-ts-mode
   "const f = (x: number): number => ‸x;
"
   #'tessera-javascript-utils-toggle-async
   "const f = async (x: number): number => x;
"))

(ert-deftest tessera-javascript-utils-test-async-static-method ()
  (tessera-javascript-utils-test--check
   #'js-ts-mode
   "class A {
  static ‸m() {}
}
"
   #'tessera-javascript-utils-toggle-async
   "class A {
  static async m() {}
}
"))

(ert-deftest tessera-javascript-utils-test-async-static-method-off ()
  (tessera-javascript-utils-test--check
   #'js-ts-mode
   "class A {
  static async ‸m() {}
}
"
   #'tessera-javascript-utils-toggle-async
   "class A {
  static m() {}
}
"))

;;;; Kill

(ert-deftest tessera-javascript-utils-test-kill-arguments ()
  (tessera-javascript-utils-test--with-kill-ring
    (tessera-javascript-utils-test--check
     #'js-ts-mode
     "foo(a, ‸b, c);
"
     #'tessera-javascript-utils-kill
     "foo(a, ‸);
")
    (should (equal (current-kill 0) "b, c"))))

(ert-deftest tessera-javascript-utils-test-kill-line ()
  (tessera-javascript-utils-test--with-kill-ring
    (tessera-javascript-utils-test--check
     #'js-ts-mode
     "‸let x = 1;
let y = 2;
"
     #'tessera-javascript-utils-kill
     "‸
let y = 2;
")
    (should (equal (current-kill 0) "let x = 1;"))))

;;;; Slurp, barf, unwrap and wrap

(ert-deftest tessera-javascript-utils-test-slurp ()
  (tessera-javascript-utils-test--check
   #'js-ts-mode
   "if (a) {
  ‸b();
}
c();
d();
"
   #'tessera-javascript-utils-forward-slurp
   "if (a) {
  b();
  c();
}
d();
"))

(ert-deftest tessera-javascript-utils-test-barf ()
  (tessera-javascript-utils-test--check
   #'js-ts-mode
   "if (a) {
  ‸b();
  c();
}
d();
"
   #'tessera-javascript-utils-forward-barf
   "if (a) {
  b();
}
c();
d();
"))

(ert-deftest tessera-javascript-utils-test-unwrap-statement ()
  (tessera-javascript-utils-test--check
   #'js-ts-mode
   "function f() {
  if (a) {
    ‸b();
  }
}
"
   #'tessera-javascript-utils-unwrap
   "function f() {
  b();
}
"))

(ert-deftest tessera-javascript-utils-test-unwrap-region ()
  (tessera-javascript-utils-test--check
   #'js-ts-mode
   "if (a) {
‸  b();
  c();‸
}
"
   #'tessera-javascript-utils-unwrap
   "b();
c();
"))

(ert-deftest tessera-javascript-utils-test-wrap-in-for-of ()
  (tessera-javascript-utils-test--check
   #'js-ts-mode
   "function f() {
  ‸g(item);
}
"
   #'tessera-javascript-utils-wrap-in-for-of
   "function f() {
  for (const item of ‸) {
    g(item);
  }
}
"))

(ert-deftest tessera-javascript-utils-test-print-path ()
  (tessera-javascript-utils-test--with-kill-ring
    (tessera-javascript-utils-test--check
     #'js-ts-mode
     "const x = {a: [1, {\"b-c\": ‸2}]};
"
     #'tessera-javascript-utils-print-path
     "const x = {a: [1, {\"b-c\": 2}]};
")
    (should (equal (current-kill 0) "a[1][\"b-c\"]"))))

(ert-deftest tessera-javascript-utils-test-print-path-punctuation ()
  ;; Punctuation in an array stands for the array, not an element
  (dolist (text '("const x = {a: ‸[1, 2]};\n" "const x = {a: [[1]‸, 2]};\n"))
    (tessera-javascript-utils-test--with-kill-ring
      (tessera-javascript-utils-test--check
       #'js-ts-mode text #'tessera-javascript-utils-print-path (string-replace "‸" "" text))
      (should (equal (current-kill 0) "a")))))

(ert-deftest tessera-javascript-utils-test-print-path-string-keys ()
  ;; String keys keep their quotes and escapes
  (tessera-javascript-utils-test--with-kill-ring
    (tessera-javascript-utils-test--check
     #'js-ts-mode
     "const x = {\"a\\\"b\": {'c-d': ‸1}};\n"
     #'tessera-javascript-utils-print-path
     "const x = {\"a\\\"b\": {'c-d': 1}};\n")
    (should (equal (current-kill 0) "[\"a\\\"b\"]['c-d']"))))

;;;; Parameters

(ert-deftest tessera-javascript-utils-test-introduce-parameter ()
  (tessera-javascript-utils-test--check
   #'js-ts-mode
   "function f(a) {
  return a + ‸1;
}
f(2);
"
   #'tessera-javascript-utils-introduce-parameter
   "function f(a, n) {
  return a + n;
}
f(2, 1);
"
   "n"))

(ert-deftest tessera-javascript-utils-test-introduce-parameter-bare-arrow ()
  (tessera-javascript-utils-test--check
   #'js-ts-mode
   "const g = x => x * ‸2;
g(3);
"
   #'tessera-javascript-utils-introduce-parameter
   "const g = (x, n) => x * n;
g(3, 2);
"
   "n"))

(ert-deftest tessera-javascript-utils-test-localize-parameter ()
  (tessera-javascript-utils-test--check
   #'js-ts-mode
   "function f(a, ‸b) {
  return a + b;
}
f(1, 2);
f(3, 2);
"
   #'tessera-javascript-utils-localize-parameter
   "function f(a) {
  const b = 2;
  return a + b;
}
f(1);
f(3);
"))

(ert-deftest tessera-javascript-utils-test-localize-argument ()
  (tessera-javascript-utils-test--check
   #'js-ts-mode
   "f(1, ‸2);
function f(a, b) {
  return a + b;
}
"
   #'tessera-javascript-utils-localize-parameter
   "f(1);
function f(a) {
  const b = 2;
  return a + b;
}
"))

(ert-deftest tessera-javascript-utils-test-localize-typed-parameter ()
  (tessera-javascript-utils-test--check
   #'typescript-ts-mode
   "function f(‸a: number) {
  return a;
}
f(1);
"
   #'tessera-javascript-utils-localize-parameter
   "function f() {
  const a: number = 1;
  return a;
}
f();
"))

;;;; Package detection

(ert-deftest tessera-javascript-utils-test-bun ()
  (tessera-javascript-utils-test--with-package dir
      '(("package.json" . "{\"scripts\": {\"build\": \"tsc\", \"test\": \"vitest run\"}}")
        ("bun.lock" . "{}"))
    (let* ((default-directory (expand-file-name "src/" dir))
           (root (tessera-javascript-utils-package-root)))
      (should (file-equal-p root dir))
      (should (eq (tessera-javascript-utils--tool root) 'bun))
      (should (equal (tessera-javascript-utils-test--strip
                      (tessera-javascript-utils--command 'bun :run "build"))
                     "bun run --bun build"))
      (should (equal (tessera-javascript-utils--scripts root)
                     '(("build" . "tsc") ("test" . "vitest run")))))))

(ert-deftest tessera-javascript-utils-test-package-manager-field ()
  (tessera-javascript-utils-test--with-package dir
      '(("package.json" . "{\"packageManager\": \"pnpm@9.15.0+sha512.abc\"}")
        ("package-lock.json" . "{}"))
    (should (eq (tessera-javascript-utils--tool dir) 'pnpm))))

(ert-deftest tessera-javascript-utils-test-workspace-lockfile ()
  (tessera-javascript-utils-test--with-package dir
      '(("package.json" . "{\"private\": true}")
        ("pnpm-lock.yaml" . "lockfileVersion: '9.0'\n")
        ("packages/a/package.json" . "{\"name\": \"a\"}")
        ("packages/a/src/index.js" . ""))
    (let* ((default-directory (expand-file-name "packages/a/src/" dir))
           (root (tessera-javascript-utils-package-root)))
      (should (file-equal-p root (expand-file-name "packages/a/" dir)))
      (should (eq (tessera-javascript-utils--tool root) 'pnpm)))))

(ert-deftest tessera-javascript-utils-test-nearest-lockfile ()
  (tessera-javascript-utils-test--with-package dir
      '(("package.json" . "{\"private\": true}")
        ("yarn.lock" . "")
        ("packages/a/package.json" . "{\"name\": \"a\"}")
        ("packages/a/package-lock.json" . "{}"))
    (should (eq (tessera-javascript-utils--tool dir) 'yarn))
    (should (eq (tessera-javascript-utils--tool (expand-file-name "packages/a/" dir))
                'npm))))

(ert-deftest tessera-javascript-utils-test-deno ()
  ;; JSONC with comments, trailing commas, and comment starters and
  ;; trailing commas inside strings, which have to stay.  `syntax-ppss'
  ;; moving point made the reader find the same `//' in a string forever.
  (tessera-javascript-utils-test--with-package dir
      '(("deno.jsonc" . "// Tasks of the package
{
  /* Tasks run by `deno task'. */
  \"tasks\": {
    \"dev\": \"deno run --watch main.ts\", // the server
    \"url\": \"echo https://example.com/* // a,}\",
    \"build\": {
      \"command\": \"deno compile main.ts\",
      \"description\": \"Compile\",
    },
  },
  \"imports\": {
    \"@std/assert\": \"jsr:@std/assert@1\",
  },
}
"))
    (tessera-javascript-utils-test--with-loop-guard
      (should (eq (tessera-javascript-utils--tool dir) 'deno))
      (should (equal (tessera-javascript-utils--scripts dir)
                     '(("dev" . "deno run --watch main.ts")
                       ("url" . "echo https://example.com/* // a,}")
                       ("build" . "deno compile main.ts"))))
      (should (equal (tessera-javascript-utils--dependencies dir) '("@std/assert"))))
    (should (equal (tessera-javascript-utils-test--strip
                    (tessera-javascript-utils--command 'deno :add-dev "jsr:@std/path"))
                   "deno add --dev jsr\\:\\@std/path"))))

(ert-deftest tessera-javascript-utils-test-npm ()
  (tessera-javascript-utils-test--with-package dir
      '(("package.json" . "{
  \"dependencies\": {\"react\": \"^19.0.0\"},
  \"devDependencies\": {\"@types/node\": \"^22.0.0\"}
}"))
    (should (eq (tessera-javascript-utils--tool dir) 'npm))
    (should (equal (tessera-javascript-utils--dependencies dir) '("react" "@types/node")))
    (should (equal (tessera-javascript-utils-test--strip
                    (tessera-javascript-utils--command 'npm :add "left pad" "a;b"))
                   "npm install left\\ pad a\\;b"))
    (should (equal (tessera-javascript-utils-test--strip
                    (tessera-javascript-utils--command 'npm :install))
                   "npm install"))))

(ert-deftest tessera-javascript-utils-test-no-package ()
  (tessera-javascript-utils-test--with-package dir nil
    (let ((default-directory dir))
      (should-not (tessera-javascript-utils-package-root))
      (should-error (tessera-javascript-utils-install) :type 'user-error))))

;;;; Running scripts

(defconst tessera-javascript-utils-test--escape-regexp "\e"
  "Regexp matching escape codes, e.g. colours or a progress spinner's.")

(defun tessera-javascript-utils-test--run-script (tool files)
  "Run script `answer' of a package with FILES managed by TOOL.
The package is in a directory named after TOOL.  Return the text of the
compilation buffer once the script has finished successfully."
  (tessera-javascript-utils-test--with-package dir
      (mapcar (lambda (file) (cons (format "%s/%s" tool (car file)) (cdr file)))
              files)
    (let* ((default-directory (expand-file-name (format "%s/" tool) dir))
           (status nil)
           (compilation-finish-functions (list (lambda (_buffer message)
                                                 (setq status message))))
           (deadline (+ (float-time) 60))
           buffer)
      (should (eq (tessera-javascript-utils--tool default-directory) tool))
      (unwind-protect
          (progn
            (setq buffer (tessera-javascript-utils-run "answer"))
            (while (and (not status) (< (float-time) deadline))
              (accept-process-output nil 0.1))
            (should (equal status "finished\n"))
            (should (equal (buffer-name buffer)
                           (format "*%s: %s*" tool
                                   (tessera-javascript-utils-test--strip
                                    (tessera-javascript-utils--command tool :run "answer")))))
            (with-current-buffer buffer
              (buffer-string)))
        (when (buffer-live-p buffer)
          (let ((kill-buffer-query-functions nil))
            (kill-buffer buffer)))))))

(defconst tessera-javascript-utils-test--node-script
  "{\"scripts\": {\"answer\": \"node -e 'console.log(6 * 7)'\"}}"
  "A package.json whose script `answer' prints 42 with Node.js.")

(ert-deftest tessera-javascript-utils-test-run-npm ()
  (let ((output (tessera-javascript-utils-test--run-script
                 'npm `(("package.json" . ,tessera-javascript-utils-test--node-script)))))
    (should (string-match-p "^42$" output))
    (should-not (string-match-p tessera-javascript-utils-test--escape-regexp output))))

(ert-deftest tessera-javascript-utils-test-run-pnpm ()
  (let ((output (tessera-javascript-utils-test--run-script
                 'pnpm `(("package.json" . ,tessera-javascript-utils-test--node-script)
                         ("pnpm-lock.yaml" . "lockfileVersion: '9.0'\n")))))
    (should (string-match-p "^42$" output))
    (should-not (string-match-p tessera-javascript-utils-test--escape-regexp output))))

(ert-deftest tessera-javascript-utils-test-run-yarn ()
  (let ((output (tessera-javascript-utils-test--run-script
                 'yarn `(("package.json" . ,tessera-javascript-utils-test--node-script)
                         ("yarn.lock" . "")))))
    (should (string-match-p "^42$" output))
    (should-not (string-match-p tessera-javascript-utils-test--escape-regexp output))))

(ert-deftest tessera-javascript-utils-test-run-bun ()
  (let ((output (tessera-javascript-utils-test--run-script
                 'bun `(("package.json" . ,tessera-javascript-utils-test--node-script)
                        ("bun.lock" . "{}")))))
    (should (string-match-p "^42$" output))
    (should-not (string-match-p tessera-javascript-utils-test--escape-regexp output))))

(ert-deftest tessera-javascript-utils-test-run-deno ()
  (let ((output (tessera-javascript-utils-test--run-script
                 'deno '(("deno.json" . "{\"tasks\": {\"answer\": \"deno eval 'console.log(6 * 7)'\"}}")))))
    (should (string-match-p "^42$" output))
    (should-not (string-match-p tessera-javascript-utils-test--escape-regexp output))))

;;; javascript-utils.el ends here
