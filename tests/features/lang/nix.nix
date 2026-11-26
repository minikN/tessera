{
  lib,
  platform,
  expect,
  emacsCheck,
  ...
}:

{
  emacs = emacsCheck {
    platform = platform;
    features = {
      emacs.enable = true;
      emacs.eglot.enable = true;
      emacs.treesit.enable = true;
      nix.enable = true;
    };
    script = # elisp
      ''
        (setq treesit-auto-install-grammar 'never)
        (require 'tessera-nix)
        (require 'tessera-eglot)
        (require 'polymode)
        (require 'eglot)

        (unless (featurep 'polymode)
          (error "Nix did not load polymode"))
        (when (featurep 'nix-mode)
          (error "Nix installs and loads nix-mode despite tree-sitter"))
        (unless (equal (cdr (assoc "\\.nix\\'" auto-mode-alist))
                       'tessera-nix-polymode)
          (error "Nix files do not use tessera-nix-polymode"))
        (unless (member 'eglot--before-change
                        polymode-run-these-before-change-functions-in-other-buffers)
          (error "Polymode does not forward Eglot's before-change hook"))
        (unless (member 'eglot--after-change
                        polymode-run-these-after-change-functions-in-other-buffers)
          (error "Polymode does not forward Eglot's after-change hook"))

        (with-temp-buffer
          (setq buffer-file-name (expand-file-name "test.nix" (getenv "TMPDIR"))
                default-directory (getenv "TMPDIR"))
          (insert "{\n  value = # elisp\n  '''\n    (message \"hello\")\n  ''';\n}\n")
          (tessera-nix-polymode)
          ;; Point must be in the host span when starting the Nix server;
          ;; polymode's post-command hook switches to the buffer at point.
          (run-hooks 'post-command-hook)
          (eglot-ensure)
          (unless (eglot-current-server)
            (error "Eglot did not start nil in a Nix polymode buffer"))
          (goto-char (point-min))
          (search-forward "message")
          (let ((span (pm-innermost-span)))
            (unless (eq (oref (nth 3 span) mode) 'emacs-lisp-mode)
              (error "Tagged string did not select emacs-lisp-mode: %S" span)))
          (goto-char (point-min))
          (search-forward "(message")
          (end-of-line)
          (let ((pos (point)))
            (with-current-buffer (pm-span-buffer (pm-innermost-span pos))
              (goto-char pos)
              (insert "\n    ;; preserved-by-eglot-format")))
          (eglot-format-buffer)
          (goto-char (point-min))
          (unless (search-forward "preserved-by-eglot-format" nil t)
            (error "Eglot formatting discarded a polymode inner-buffer edit"))
          (eglot-shutdown (eglot-current-server)))

        (princ "Nix polymode and Eglot behavior is correct\n")
      '';
  };

  without-tree-sitter = expect {
    platform = platform;
    features =
      { pkgs, ... }:
      {
        emacs.enable = true;
        emacs.package = pkgs.emacs.override { withTreeSitter = false; };
        nix.enable = true;
      };
    messages = [ "features.nix: features.emacs.package is built without tree-sitter" ];
  };
}
