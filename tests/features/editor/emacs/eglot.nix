{
  platform,
  emacsCheck,
  ...
}:

{
  keys = emacsCheck {
    platform = platform;
    features = {
      emacs.enable = true;
      emacs.eglot.enable = true;
      emacs.keymaps.enable = true;
    };
    script = # elisp
      ''
        (require 'eglot)

        ;; Activate the keymap of a buffer Eglot manages without a server
        (with-temp-buffer
          (setq-local eglot--managed-mode t)
          (unless (eq (key-binding (kbd "C-c c d")) 'tessera-eglot-next-doc)
            (error "C-c c d does not show the next documentation"))
          (unless (eq (key-binding (kbd "M-d")) 'kill-word)
            (error "Eglot overrides kill-word")))

        (princ "Eglot keys are correct\n")
      '';
  };
}
