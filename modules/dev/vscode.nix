_: {
  flake.modules.home.vscode = {pkgs, ...}: {
    programs.vscode = {
      enable = true;
      package = pkgs.vscode;
      # Fully declarative: extensions come from the store, settings from the
      # vendored JSON below. No mutable extensions dir, no marketplace installs.
      mutableExtensionsDir = false;
      profiles.default = {
        userSettings = ./vscode-settings.json;
        extensions = with pkgs.vscode-marketplace; [
          bierner.markdown-mermaid
          charliermarsh.ruff
          eamodio.gitlens
          enkia.tokyo-night
          janisdd.vscode-edit-csv
          jnoortheen.nix-ide
          jock.svg
          kisstkondoros.vscode-gutter-preview
          ms-python.black-formatter
          ms-python.isort
          ms-vscode.makefile-tools
          ms-vscode.remote-explorer
          ms-vscode-remote.remote-ssh
          ms-vscode-remote.remote-ssh-edit
          naumovs.color-highlight
          peterj.proto
          pkief.material-icon-theme
          redhat.vscode-yaml
          streetsidesoftware.code-spell-checker
          streetsidesoftware.code-spell-checker-portuguese-brazilian
          tamasfe.even-better-toml
          yzhang.markdown-all-in-one
          zainchen.json
        ];
      };
    };
  };
}
