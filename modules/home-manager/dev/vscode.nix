{ config, lib, pkgs, ... }:

{
    programs.vscode = {
      enable = true;
      mutableExtensionsDir = false;
    };
    programs.vscode.profiles.default = {
      enableExtensionUpdateCheck = false;
      enableUpdateCheck = false;

      extensions = with pkgs.vscode-extensions; [
      ] ++ pkgs.vscode-utils.extensionsFromVscodeMarketplace [
        {
          name = "enkia";
          publisher = "tokyo-night";
          version = "1.1.2";
        }
        {
          name = "pkief";
          publisher = "material-icon-theme";
        #   version = "5.27.0";
        }
      ];

      userSettings = {
        "window.newWindowProfile" = "Default";
        "workbench.colorTheme" = "Tokyo Night";
        "workbench.iconTheme" = "material-icon-theme";
        "workbench.secondarySideBar.showLabels" =  false;
        "editor.fontSize" = 12;
        "editor.lineHeight" = 24;
        "editor.fontFamily" = "JetBrainsMono Nerd Font";
        "editor.fontLigatures" =  false;
        "editor.wordWrap" = "bounded";
        "editor.wordWrapColumn" = 100;
        "editor.cursorSurroundingLines" = 50;
        "editor.lineNumbers" =  "relative";
        "editor.formatOnType"= true;
        "editor.formatOnPaste"= true;
        "editor.unicodeHighlight.invisibleCharacters"= true;
        "files.autoSave"=  "afterDelay";
        "editor.formatOnSaveMode" = "file";
        "editor.formatOnSave" = true;
        "editor.codeActionsOnSave" = {
            "source.sortImports" = "explicit";
            "source.fixAll.markdownlint" = "explicit";
            "source.fixAll" = "explicit";
            "source.organizeImports" = "explicit";
        };
        "editor.rulers"= [
            160
            200
        ];

        "files.autoSave" = "afterDelay";
        "files.autoSaveDelay" = 100;
        "files.associations" = {
            "*.hcl" = "terraform"
        };

        "terminal.integrated.fontFamily" = "JetBrainsMono Nerd Font";
        "explorer.confirmDelete" = false;
        "explorer.confirmDragAndDrop" = false;
        "cSpell.language" = " en,pt_BR";
        "diffEditor.ignoreTrimWhitespace" = false;
        "diffEditor.codeLens" = true;

        "[markdown]" = {
          "editor.wordWrap" = "bounded";
        };
        "nix.enableLanguageServer" = true;
        "nix.serverPath" = "nixd";
        "nix.formatterPath" = "nixpkgs-fmt";
        "nix.serverSettings" = {
          "nixd" = {
            "formatting" = {
              "command" = [ "nixpkgs-fmt" ];
            };
            # "options" = {
            #   # By default, this entry will be read from `import <nixpkgs> { }`.
            #   # You can write arbitary Nix expressions here, to produce valid "options" declaration result.
            #   # Tip: for flake-based configuration, utilize `builtins.getFlake`
            #   "nixos" = {
            #     "expr" = "(builtins.getFlake \"/synced/Nix/cfg\").nixosConfigurations.<name>.options";
            #   };
            #   "home-manager" = {
            #     "expr" = "(builtins.getFlake \"/synced/Nix/cfg\").homeConfigurations.<name>.options";
            #   };
            # };
          };
        };

      
        "git.enableCommitSigning" = false;
        "git.enableSmartCommit" = true;
        "git.fetchOnPull" = true;
        "git.confirmSync" = false;
        "git.ignoreRebaseWarning" = true;
        "git.autofetch" = "all";
        "gitlens.defaultDateLocale" = null;
        "security.workspace.trust.untrustedFiles" = "open";
        "extensions.verifySignature" = false;
        "update.showReleaseNotes" = false;
      };
    };
}