_: {
  flake.modules.home.vscode = {pkgs, ...}: {
    programs.vscode = {
      enable = true;
      package = pkgs.vscode.override {
        commandLineArgs = ''
          --disable-extension=GitHub.copilot-chat
          --disable-extension=vscode.debug-auto-launch
          --disable-extension=vscode.debug-server-ready
          --disable-extension=ms-vscode.js-debug
          --disable-extension=ms-vscode.js-debug-companion
        '';
      };
      # Fully declarative: extensions come from the store, settings from the
      # vendored JSON below. No mutable extensions dir, no marketplace installs.
      mutableExtensionsDir = false;
      profiles.default = {
        userSettings = ./vscode-settings.json;
        extensions = with pkgs.vscode-marketplace; [
          charliermarsh.ruff
          enkia.tokyo-night
          jnoortheen.nix-ide
          ms-python.black-formatter
          ms-python.isort
          pkief.material-icon-theme
          redhat.vscode-yaml
          streetsidesoftware.code-spell-checker
          streetsidesoftware.code-spell-checker-portuguese-brazilian
          tamasfe.even-better-toml
          yzhang.markdown-all-in-one
        ];
      };
    };
  };
}
