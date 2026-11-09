{
  mkFeature,
  mkElispConfig,
  ...
}:

mkFeature {
  name = [
    "emacs"
    "compilation"
  ];

  doc = {
    summary = "Compilation buffers that show tool output as in a terminal";
    description = ''
      Tunes the buffers of `M-x compile`, `M-x project-compile` and the
      commands of features that run tools in one (e.g. the javascript
      feature).

      - Colours from escape codes show as colours; other control sequences,
        e.g. those of progress bars, are removed
      - Long lines, e.g. progress bars, are no longer cut to `[...]`
      - The buffer follows the output; `M-g n` and `M-g p` go to the errors
      - Modified buffers are saved without asking before compiling
      - `project-compile` names its buffer after the project, so each
        project keeps its own
      - Interactive compilations (`C-u M-x compile`) and other comint
        buffers such as `M-x shell` jump to the bottom on input and output
    '';
  };

  home =
    { pkgs, ... }:
    mkElispConfig pkgs {
      name = "tessera-compilation";
      summary = "Compilation buffers that show tool output as in a terminal";

      config = ''
        (setopt compilation-max-output-line-length nil
                compilation-scroll-output t
                compilation-ask-about-save nil
                project-compilation-buffer-name-function #'project-prefixed-buffer-name
                comint-scroll-to-bottom-on-input t
                comint-scroll-to-bottom-on-output t)

        (add-hook 'compilation-filter-hook #'ansi-color-compilation-filter)
      '';
    };
}
