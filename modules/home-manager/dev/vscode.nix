{
  pkg,
  config,
  lib,
  pkgs,
  ...
}: {
  programs.vscode = {
    enable = true;
    package =  (pkgs.vscode.override{ isInsiders = true; }).overrideAttrs (oldAttrs: rec {
      src = (builtins.fetchTarball {
        url = "https://update.code.visualstudio.com/latest/linux-x64/insider";
        sha256 = "0j7m5mnzhh2g53rhnn0lgih3xc5i5nm9zq1ibmmfxps6hzgyqnga";
      });
      version = "latest";
    });
    mutableExtensionsDir = true;
    #https://github.com/iosmanthus/code-insiders-flake
  };
  # programs.vscode.profiles.default = {
  #   enableExtensionUpdateCheck = false;
  #   enableUpdateCheck = false;

  #   extensions = with pkgs.vscode-extensions;
  #     [
  #     ]
  #     ++ pkgs.vscode-utils.extensionsFromVscodeMarketplace [
  #     ];

  #   userSettings = {
  #     "window.newWindowProfile" = "Default";
  #     "workbench.colorTheme" = "Tokyo Night";
  #     "workbench.iconTheme" = "material-icon-theme";
  #     "workbench.secondarySideBar.showLabels" = false;
  #     "editor.fontSize" = 12;
  #     "editor.lineHeight" = 24;
  #     "editor.fontFamily" = "JetBrainsMono Nerd Font";
  #     "editor.fontLigatures" = false;
  #     "editor.wordWrap" = "bounded";
  #     "editor.wordWrapColumn" = 100;
  #     "editor.cursorSurroundingLines" = 50;
  #     "editor.lineNumbers" = "relative";
  #     "editor.formatOnType" = true;
  #     "editor.formatOnPaste" = true;
  #     "editor.unicodeHighlight.invisibleCharacters" = true;
  #     "editor.formatOnSaveMode" = "file";
  #     "editor.formatOnSave" = true;
  #     "editor.codeActionsOnSave" = {
  #       "source.sortImports" = "explicit";
  #       "source.fixAll.markdownlint" = "explicit";
  #       "source.fixAll" = "explicit";
  #       "source.organizeImports" = "explicit";
  #     };
  #     "editor.rulers" = [
  #       160
  #       200
  #     ];

  #     "files.autoSave" = "afterDelay";
  #     "files.associations" = {
  #       "*.hcl" = "terraform";
  #     };

  #     "terminal.integrated.fontFamily" = "JetBrainsMono Nerd Font";
  #     "explorer.confirmDelete" = false;
  #     "explorer.confirmDragAndDrop" = false;
  #     "cSpell.language" = " en,pt_BR";
  #     "diffEditor.ignoreTrimWhitespace" = false;
  #     "diffEditor.codeLens" = true;

  #     "[markdown]" = {
  #       "editor.wordWrap" = "bounded";
  #     };
  #     "nix.enableLanguageServer" = true;
  #     "nix.serverPath" = "nixd";
  #     "nix.formatterPath" = "nixpkgs-fmt";
  #     "nix.serverSettings" = {
  #       "nixd" = {
  #         "formatting" = {
  #           "command" = ["nixpkgs-fmt"];
  #         };
  #         # "options" = {
  #         #   # By default, this entry will be read from `import <nixpkgs> { }`.
  #         #   # You can write arbitary Nix expressions here, to produce valid "options" declaration result.
  #         #   # Tip: for flake-based configuration, utilize `builtins.getFlake`
  #         #   "nixos" = {
  #         #     "expr" = "(builtins.getFlake \"/synced/Nix/cfg\").nixosConfigurations.<name>.options";
  #         #   };
  #         #   "home-manager" = {
  #         #     "expr" = "(builtins.getFlake \"/synced/Nix/cfg\").homeConfigurations.<name>.options";
  #         #   };
  #         # };
  #       };
  #     };

  #     "git.enableCommitSigning" = false;
  #     "git.enableSmartCommit" = true;
  #     "git.fetchOnPull" = true;
  #     "git.confirmSync" = false;
  #     "git.ignoreRebaseWarning" = true;
  #     "git.autofetch" = "all";
  #     "gitlens.defaultDateLocale" = null;
  #     "security.workspace.trust.untrustedFiles" = "open";
  #     "extensions.verifySignature" = false;
  #     "update.showReleaseNotes" = false;
  #   };
  # };
}
