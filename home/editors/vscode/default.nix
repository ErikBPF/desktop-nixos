{pkgs, ...}: {
  programs.vscode = {
    enable = true;
    enableExtensionUpdateCheck = true;
    enableUpdateCheck = false;
    extensions = with pkgs.vscode-extensions;
      [
        bbenoist.nix

        formulahendry.auto-close-tag
        christian-kohler.path-intellisense
        naumovs.color-highlight
        usernamehw.errorlens
        eamodio.gitlens

        esbenp.prettier-vscode
        kamadorueda.alejandra
        astro-build.astro-vscode
        bradlc.vscode-tailwindcss
      ]
      ++ pkgs.vscode-utils.extensionsFromVscodeMarketplace [];
    userSettings = {
      "workbench.iconTheme" = "catppuccin-perfect-mocha";
      "workbench.colorTheme" = "Tsuki";
      "editor.fontFamily" = "AestheticIosevka Nerd Font, Catppuccin Perfect Mocha, 'monospace', monospace";
      "editor.fontSize" = 13;
      "editor.fontLigatures" = true;
      "files.trimTrailingWhitespace" = true;
      "terminal.integrated.fontFamily" = "AestheticIosevka Nerd Font Mono";
      "window.titleBarStyle" = "custom";
      "terminal.integrated.defaultProfile.linux" = "zsh";
      "terminal.integrated.cursorBlinking" = true;
      "terminal.integrated.enableVisualBell" = false;
      "editor.formatOnPaste" = true;
      "editor.formatOnSave" = true;
      "editor.formatOnType" = false;
      "editor.minimap.enabled" = false;
      "editor.minimap.renderCharacters" = false;
      "editor.overviewRulerBorder" = false;
      "editor.renderLineHighlight" = "all";
      "editor.inlineSuggest.enabled" = true;
      "editor.smoothScrolling" = true;
      "editor.suggestSelection" = "first";
      "editor.guides.indentation" = true;
      "editor.guides.bracketPairs" = true;
      "editor.bracketPairColorization.enabled" = true;
      "window.restoreWindows" = "all";
      "window.menuBarVisibility" = "toggle";
      "workbench.panel.defaultLocation" = "right";
      "workbench.list.smoothScrolling" = true;
      "security.workspace.trust.enabled" = false;
      "explorer.confirmDelete" = false;
      "breadcrumbs.enabled" = true;
      "telemetry.telemetryLevel" = "off";
      "workbench.startupEditor" = "newUntitledFile";
      "editor.cursorBlinking" = "expand";
      "security.workspace.trust.untrustedFiles" = "open";
      "security.workspace.trust.banner" = "never";
      "security.workspace.trust.startupPrompt" = "never";
      "workbench.sideBar.location" = "left";
      "editor.tabSize" = 2;
      "editor.wordWrap" = "on";
      "workbench.editor.tabActionLocation" = "left";
    };
  };
}
