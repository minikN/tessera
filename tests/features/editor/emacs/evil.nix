{
  platform,
  emacsCheck,
  ...
}:

let
  ## Elisp pressing keys in buffers and the minibuffer
  helpers = # elisp
    ''
      (defun tessera-test-keys (mode text keys)
        "Press KEYS in a new MODE buffer with TEXT and point at its start.
      Return the buffer's text, point and Evil state afterwards."
        (let ((buffer (generate-new-buffer "test")))
          (switch-to-buffer buffer)
          (insert text)
          (goto-char (point-min))
          (funcall mode)
          (execute-kbd-macro (kbd keys))
          (prog1 (list (buffer-string) (point) evil-state)
            (kill-buffer buffer))))

      (defun tessera-test-expect (mode text keys expected)
        "Check that KEYS turn TEXT in a MODE buffer into EXPECTED."
        (let ((result (car (tessera-test-keys mode text keys))))
          (unless (equal result expected)
            (error "%s in %s turned %S into %S, not %S" keys mode text result expected))))

      (defun tessera-test-minibuffer-binding (key)
        "Return the command KEY runs in the minibuffer."
        (let (binding)
          (keymap-global-set "<f12>"
                             (lambda ()
                               (interactive)
                               (minibuffer-with-setup-hook
                                   (lambda () (setq binding (key-binding (kbd key))))
                                 (read-from-minibuffer "Test: "))))
          (execute-kbd-macro (kbd "<f12> RET"))
          binding))
    '';
in
{
  wiring = emacsCheck {
    platform = platform;
    features = {
      emacs.enable = true;
      emacs.completion.enable = true;
      emacs.evil.enable = true;
    };
    script = # elisp
      ''
        (require 'tessera-evil)
        ${helpers}

        ;; Evil Commentary and Surround
        (tessera-test-expect 'emacs-lisp-mode "(foo)\n(bar)\n" "gcc" ";; (foo)\n(bar)\n")
        (tessera-test-expect 'text-mode "foo bar" "ysiw)" "(foo) bar")

        ;; Undo and redo with undo-fu, undoing an insert session in steps
        (tessera-test-expect 'text-mode "" "ifoo <escape> u" "")
        (tessera-test-expect 'text-mode "" "ifoo <escape> u C-r" "foo")
        (tessera-test-expect 'text-mode "" "ifoo RET bar <escape> u" "foo\n")

        ;; Insert state keys
        (pcase-let ((`(,text ,_ ,state) (tessera-test-keys 'text-mode "" "ifoo C-g")))
          (unless (and (equal text "foo") (eq state 'normal))
            (error "C-g in insert state left %S in %s state" text state)))
        (tessera-test-expect 'text-mode "ab\ncd" "j I C-h" "abcd")

        ;; Operators move by physical lines; batch Emacs cannot show that `j'
        ;; and `k' move by screen lines, so check what they run instead
        (tessera-test-expect 'text-mode "a\nb\nc\n" "dj" "c\n")
        (with-temp-buffer
          (text-mode)
          (unless (and (eq (key-binding "j") 'evil-next-visual-line)
                       (eq (key-binding "k") 'evil-previous-visual-line))
            (error "j and k do not move by screen lines")))

        (tessera-test-expect 'text-mode "foo" ">>" (concat (make-string tab-width ?\s) "foo"))
        (tessera-test-expect 'text-mode "abcdef" "C-M-u x" "ef")

        ;; Window layout undo and redo
        (delete-other-windows)
        (tessera-test-keys 'text-mode "" "C-w v C-w u")
        (unless (one-window-p)
          (error "C-w u did not undo the window split"))
        (tessera-test-keys 'text-mode "" "C-w v C-w u C-w U")
        (when (one-window-p)
          (error "C-w U did not redo the window split"))
        (delete-other-windows)

        ;; Initial states, after Evil Collection has set up each mode
        (require 'term)
        (dolist (mode '(Custom-mode eshell-mode term-mode))
          (with-current-buffer (generate-new-buffer "test")
            (funcall mode)
            (unless (eq evil-state 'emacs)
              (error "%s starts in %s state, not Emacs state" mode evil-state))))
        (with-current-buffer (messages-buffer)
          (unless (eq evil-state 'normal)
            (error "Messages starts in %s state, not normal state" evil-state)))

        ;; Minibuffer history, searched with Consult, and Escape quitting it
        (defvar tessera-test-history nil)
        (let (result)
          (keymap-global-set "<f12>"
                             (lambda ()
                               (interactive)
                               (setq tessera-test-history '("newest" "older")
                                     result (read-from-minibuffer
                                             "Test: " nil nil nil 'tessera-test-history))))
          (execute-kbd-macro (kbd "<f12> C-k C-k RET"))
          (unless (equal result "older")
            (error "C-k in the minibuffer gave %S, not the older history element" result))
          (execute-kbd-macro (kbd "<f12> C-k C-k C-j RET"))
          (unless (equal result "newest")
            (error "C-j in the minibuffer gave %S, not the newer history element" result))
          (unless (eq (condition-case nil
                          (execute-kbd-macro (kbd "<f12> <escape>"))
                        (quit 'quit))
                      'quit)
            (error "Escape does not quit the minibuffer")))
        (unless (eq (tessera-test-minibuffer-binding "C-r") 'consult-history)
          (error "C-r does not search the minibuffer history with Consult"))

        ;; Org navigation and Evil Org
        (pcase-let ((`(,_ ,point) (tessera-test-keys 'org-mode "* a\n* b\n" "C-j")))
          (unless (= point 5)
            (error "C-j in Org did not move to the next heading")))
        (pcase-let ((`(,_ ,point) (tessera-test-keys 'org-mode "* a\n* b\n" "j C-k")))
          (unless (= point 1)
            (error "C-k in Org did not move to the previous heading")))
        (tessera-test-expect 'org-mode "* a\n* b\n" "M-j" "* b\n* a\n")
        (tessera-test-expect 'org-mode "* a\n* b\n" "j M-k" "* b\n* a\n")
        (with-temp-buffer
          (org-mode)
          (unless (bound-and-true-p evil-org-mode)
            (error "Evil Org is not enabled in Org buffers")))
        (let ((org-agenda-files nil))
          (org-agenda-list)
          (unless (bound-and-true-p evil-org-mode)
            (error "Evil Org is not enabled in the Org agenda")))

        (princ "Evil behavior is correct\n")
      '';
  };

  state-messages = emacsCheck {
    platform = platform;
    features = {
      emacs.enable = true;
      emacs.evil = {
        enable = true;
        hideStateMessage = true;
      };
    };
    script = # elisp
      ''
        (require 'tessera-evil)
        ${helpers}

        ;; Batch Emacs shows no echo area, so check the settings instead
        (unless (and tessera-evil-hide-state-message
                     (null evil-insert-state-message)
                     (null evil-visual-state-message))
          (error "State messages are still displayed"))
        (customize-set-variable 'tessera-evil-hide-state-message nil)
        (unless (and evil-insert-state-message evil-visual-state-message)
          (error "Customize did not restore the state messages"))
        (customize-set-variable 'tessera-evil-hide-state-message t)
        (unless (and (null evil-insert-state-message)
                     (null evil-visual-state-message))
          (error "Customize did not hide the state messages"))
        (when (featurep 'tessera-completion)
          (error "Evil loaded completion even though it is disabled"))
        (when (eq (tessera-test-minibuffer-binding "C-r") 'consult-history)
          (error "Consult history is bound without the completion feature"))

        (princ "Evil state messages and optional Consult integration are correct\n")
      '';
  };
}
