_: {
  # Desktop-only yazi extras. Base yazi (profile-base, fleet-wide incl. servers)
  # stays a lean TUI; these bits pull GUI deps (ripdrag/GTK4), ghostty, and extra
  # binaries (ouch), so they live here and load only via profile-desktop.
  flake.modules.home.yazi-desktop = {pkgs, ...}: let
    # Tier 2 discoverability: GUI→yazi cheatsheet popup on SUPER+/ (themed rofi).
    yaziCheatsheet = pkgs.writeText "yazi-cheatsheet.txt" ''
      Ctrl+C          Copy file(s)
      Ctrl+X          Cut file(s)
      Ctrl+V          Paste
      Delete          Move to trash          (Shift+D = delete forever)
      F2              Rename
      Backspace / ←   Up to parent folder
      Enter / →       Open file / enter folder
      Home / End      First / last item
      Space           Select (multi-select)
      Ctrl+C…Ctrl+V   Copy/paste also work the yazi way: y / x / p
      Ctrl+D          Drag selection into a GUI app
      Ctrl+T          Open a terminal in this folder
      Ctrl+E          Extract archive here
      m  /  '         Save / jump to bookmark
      M               Mount / unmount USB drive
      c m             chmod
      /               Search        (n / N = next / prev match)
      .               Toggle hidden files
      ~               Yazi's own full keymap help
      q               Quit yazi      (Super+Shift+E opens Nautilus instead)
    '';
    yaziHelp = pkgs.writeShellScriptBin "yazi-help" ''
      exec ${pkgs.rofi}/bin/rofi -dmenu -i -p "yazi" \
        -mesg "GUI → yazi cheatsheet — Esc to close" < ${yaziCheatsheet}
    '';
  in {
    home.packages = [yaziHelp];
    programs.yazi = {
      # Put helper binaries on yazi's own PATH (not the whole session).
      # wl-clipboard = wl-copy, needed for yazi's `c` copy-to-clipboard menu on Wayland.
      extraPackages = [pkgs.ripdrag pkgs.ouch pkgs.wl-clipboard];

      plugins = {
        # setup = true → HM emits require("<name>"):setup(settings) in init.lua.
        git = {
          package = pkgs.yaziPlugins.git;
          setup = true;
          settings.order = 1500;
        };
        bookmarks = {
          package = pkgs.yaziPlugins.bookmarks;
          setup = true;
        };
        full-border = {
          package = pkgs.yaziPlugins.full-border;
          setup = true;
        };
        # Keymap-only plugins — no setup() call needed.
        drag = pkgs.yaziPlugins.drag;
        smart-enter = pkgs.yaziPlugins.smart-enter;
        mount = pkgs.yaziPlugins.mount;
        chmod = pkgs.yaziPlugins.chmod;
        ouch = pkgs.yaziPlugins.ouch;
      };

      flavors."tokyo-night" = pkgs.fetchFromGitHub {
        owner = "BennyOe";
        repo = "tokyo-night.yazi";
        rev = "8e6296f14daff24151c736ebd0b9b6cd89b02b03";
        hash = "sha256-LArhRteD7OQRBguV1n13gb5jkl90sOxShkDzgEf3PA0=";
      };
      theme.flavor = {
        dark = "tokyo-night";
        light = "tokyo-night";
      };

      settings.plugin = {
        # git status as linemode column (id field dropped: yazi > v26.1.22).
        prepend_fetchers = [
          {
            url = "*";
            run = "git";
            group = "git";
          }
          {
            url = "*/";
            run = "git";
            group = "git";
          }
        ];
        # Peek inside archives without extracting.
        prepend_previewers = [
          {
            mime = "application/{*zip,tar,bzip2,7z*,rar,xz,zstd,java-archive}";
            run = "ouch";
          }
        ];
      };

      keymap.mgr.prepend_keymap = [
        {
          on = ["<C-d>"];
          run = "plugin drag";
          desc = "Drag & drop selection to GUI apps (ripdrag)";
        }
        {
          on = ["<C-t>"];
          run = "shell 'ghostty' --orphan";
          desc = "Open a terminal in the current folder";
        }
        {
          on = ["<C-e>"];
          run = ''shell 'ouch d -y "$@"' --confirm'';
          desc = "Extract archive(s) here (ouch)";
        }
        {
          on = ["l"];
          run = "plugin smart-enter";
          desc = "Enter dir or open file";
        }
        {
          on = ["m"];
          run = "plugin bookmarks save";
          desc = "Save bookmark";
        }
        {
          on = ["'"];
          run = "plugin bookmarks jump";
          desc = "Jump to bookmark";
        }
        {
          on = ["b" "d"];
          run = "plugin bookmarks delete";
          desc = "Delete bookmark";
        }
        {
          on = ["b" "D"];
          run = "plugin bookmarks delete_all";
          desc = "Delete all bookmarks";
        }
        {
          on = ["M"];
          run = "plugin mount";
          desc = "Mount manager (USB drives)";
        }
        {
          on = ["c" "m"];
          run = "plugin chmod";
          desc = "chmod selection";
        }

        # --- Tier 1: GUI muscle-memory bridge (additive — yazi natives y/x/p/d/r
        # still work; these just add the keys a nautilus user's fingers expect). ---
        {
          on = ["<C-c>"];
          run = "yank";
          desc = "Copy file(s) [GUI Ctrl+C]";
        }
        {
          on = ["<C-x>"];
          run = "yank --cut";
          desc = "Cut file(s) [GUI Ctrl+X]";
        }
        {
          on = ["<C-v>"];
          run = "paste";
          desc = "Paste [GUI Ctrl+V]";
        }
        {
          on = ["<Delete>"];
          run = "remove";
          desc = "Move to trash [GUI Delete]";
        }
        {
          on = ["<F2>"];
          run = "rename --cursor=before_ext";
          desc = "Rename [GUI F2]";
        }
        {
          on = ["<Backspace>"];
          run = "leave";
          desc = "Up to parent folder [GUI Backspace]";
        }
        {
          on = ["<Enter>"];
          run = "plugin smart-enter";
          desc = "Open file / enter folder [GUI Enter]";
        }
        {
          on = ["<Home>"];
          run = "arrow top";
          desc = "First item [GUI Home]";
        }
        {
          on = ["<End>"];
          run = "arrow bot";
          desc = "Last item [GUI End]";
        }
      ];
    };
  };
}
