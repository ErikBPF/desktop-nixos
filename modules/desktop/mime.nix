_: {
  flake.modules.home.mime = {
    config,
    lib,
    pkgs,
    ...
  }: let
    browser = "brave-browser";
    pdf = "brave-browser";
    fileManager = "yazi";
    editor = "nvim-open.desktop";
    codingTypes = [
      "text/plain"
      "text/markdown"
      "application/json"
      "application/ld+json"
      "text/x-python"
      "text/x-python3"
      "text/rust"
      "text/x-rust"
      "text/x-nix"
      "application/yaml"
      "text/yaml"
      "text/x-yaml"
      "application/toml"
      "text/x-toml"
      "text/x-lua"
      "application/x-shellscript"
      "text/x-shellscript"
      "text/x-go"
      "text/javascript"
      "application/javascript"
      "text/typescript"
      "text/jsx"
      "text/css"
      "text/x-csrc"
      "text/x-chdr"
      "text/x-c++src"
      "text/x-c++hdr"
      "text/x-java"
      "text/x-makefile"
      "text/x-cmake"
      "text/x-diff"
      "x-scheme-handler/vscode"
    ];
    opener = pkgs.writeShellScript "nvim-open" ''
      exec ${lib.getExe pkgs.python3} ${./nvim-open.py} \
        ${lib.getExe config.programs.ghostty.package} \
        ${lib.getExe config.programs.nixvim.build.package} \
        ${lib.getExe config.programs.vscode.package} "$@"
    '';
  in {
    xdg.desktopEntries.nvim-open = {
      name = "Neovim";
      genericName = "Text Editor";
      exec = "${opener} %U";
      terminal = false;
      categories = ["Development" "TextEditor"];
      mimeType = codingTypes;
    };
    xdg.mimeApps = {
      enable = true;
      defaultApplications =
        (lib.genAttrs codingTypes (_: editor))
        // {
          "text/html" = "${browser}.desktop";
          "x-scheme-handler/http" = "${browser}.desktop";
          "x-scheme-handler/https" = "${browser}.desktop";
          "x-scheme-handler/chrome" = "${browser}.desktop";
          "x-scheme-handler/about" = "${browser}.desktop";
          "x-scheme-handler/unknown" = "${browser}.desktop";
          "default-web-browser" = "${browser}.desktop";
          "application/xhtml+xml" = "${browser}.desktop";
          "application/x-extension-htm" = "${browser}.desktop";
          "application/x-extension-html" = "${browser}.desktop";
          "application/x-extension-shtml" = "${browser}.desktop";
          "application/x-extension-xhtml" = "${browser}.desktop";
          "application/x-extension-xht" = "${browser}.desktop";
          "application/pdf" = "${pdf}.desktop";
          "inode/directory" = "${fileManager}.desktop";
        };
    };
  };
}
