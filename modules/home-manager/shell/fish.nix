{pkgs, ...}: let
  aliases = import ./aliases.nix {};
in {
  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      ${pkgs.nix-your-shell}/bin/nix-your-shell --nom fish | source

      # Early return conditions
      if test "$PAGER" = "head -n 10000 | cat" -o "$COMPOSER_NO_INTERACTION" = "1"
        return
      end

      if test "$TERM_PROGRAM" = "vscode" -o "$TERM_PROGRAM" = "cursor"
        return
      end

      set -x GOPATH $XDG_DATA_HOME/go
      set -x GOPRIVATE "git.curve.tools,go.curve.tools,gitlab.com/imaginecurve"
      set -gx PATH $PATH $HOME/.krew/bin
      fish_add_path --path --append $GOPATH/bin/
      fish_add_path --path --append /usr/local/bin /usr/bin ~/.local/bin

      # fifc setup
      set -Ux fifc_editor nvim
      set -U fifc_keybinding \cx
      bind \cx _fifc
      bind -M insert \cx _fifc

      set -g fish_color_normal                  c0caf5 # Normal text color #c0caf5
      set -g fish_color_command                 7dcfff # Command color #7dcfff
      set -g fish_color_keyword                 bb9af7 # Keyword color #bb9af7
      set -g fish_color_quote                   e0af68 # Quoted text color #e0af68
      set -g fish_color_redirection             c0caf5 # Redirection color #c0caf5
      set -g fish_color_end                     ff9e64 # End color #ff9e64
      set -g fish_color_option                  bb9af7 # Option color #bb9af7
      set -g fish_color_error                   f7768e # Error color #f7768e
      set -g fish_color_param                   9d7cd8 # Parameter color #9d7cd8
      set -g fish_color_comment                 565f89 # Comment color #565f89
      set -g fish_color_selection               --background=283457 # Selection background color #283457
      set -g fish_color_search_match            --background=283457 # Search match background color #283457
      set -g fish_color_operator                9ece6a # Operator color #9ece6a
      set -g fish_color_escape                  bb9af7 # Escape sequence color #bb9af7
      set -g fish_color_autosuggestion          565f89 # Autosuggestion color #565f89

      # Completion Pager Colors
      set -g fish_pager_color_progress          565f89 # Pager progress color #565f89
      set -g fish_pager_color_prefix            7dcfff # Pager prefix color #7dcfff
      set -g fish_pager_color_completion        c0caf5 # Pager completion color #c0caf5
      set -g fish_pager_color_description       565f89 # Pager description color #565f89
      set -g fish_pager_color_selected_background --background=283457 # Pager selected background color #283457
      fish_vi_key_bindings # Enable vi mode
      set -g fish_greeting # Disable greeting

      set -g fish_cursor_default block
      set -g fish_cursor_insert line
      set -g fish_cursor_replace_one underscore

      set -g fish_vi_force_cursor 1

      # History settings
      set -g history_max 1000000


    '';

    functions = {
      fish_greeting = '''';

      envsource = ''
        for line in (cat $argv | grep -v '^#')
          set item (string split -m 1 '=' $line)
          set -gx $item[1] $item[2]
          echo "Exported key $item[1]"
        end
      '';

      y = ''
        set tmp (mktemp -t "yazi-cwd.XXXXXX")
        yazi $argv --cwd-file="$tmp"
        if read -z cwd < "$tmp"; and [ -n "$cwd" ]; and [ "$cwd" != "$PWD" ]
        	builtin cd -- "$cwd"
        end
        rm -f -- "$tmp"
      '';

      gcrb = ''
          set result (git branch -a --color=always | grep -v '/HEAD\s' | sort |
            fzf --height 50% --border --ansi --tac --preview-window right:70% \
              --preview 'git log --oneline --graph --date=short --pretty="format:%C(auto)%cd %h%d %s" (string sub -s 3 (string split ' ' {})[1]) | head -'$LINES |
            string sub -s 3 | string split ' ' -m 1)[1]

          if test -n "$result"
            if string match -r "^remotes/.*" $result > /dev/null
              git checkout --track (string replace -r "^remotes/" "" $result)
            else
              git checkout $result
            end
          end
        end
      '';

      hmg = ''
        set current_gen (home-manager generations | head -n 1 | awk '{print $7}')
        home-manager generations | awk '{print $7}' | tac | fzf --preview "echo {} | xargs -I % sh -c 'nvd --color=always diff $current_gen %' | xargs -I{} bash {}/activate"
      '';

      rgvim = ''
        rg --color=always --line-number --no-heading --smart-case "$argv" |
          fzf --ansi \
              --color "hl:-1:underline,hl+:-1:underline:reverse" \
              --delimiter : \
              --preview 'bat --color=always {1} --highlight-line {2}' \
              --preview-window 'up,60%,border-bottom,+{2}+3/3,~3' \
              --bind 'enter:become(nvim {1} +{2})'
      '';

      fish_command_not_found = ''
        # If you run the command with comma, running the same command
        # will not prompt for confirmation for the rest of the session
        if contains $argv[1] $__command_not_found_confirmed_commands
          or ${pkgs.gum}/bin/gum confirm --selected.background=2 "Run using comma?"

          # Not bothering with capturing the status of the command, just run it again
          if not contains $argv[1] $__command_not_found_confirmed_commands
            set -ga __fish_run_with_comma_commands $argv[1]
          end

          comma -- $argv
          return 0
        else
          __fish_default_command_not_found_handler $argv
        end
      '';
    };
    plugins = [
      {
        name = "bass";
        inherit (pkgs.fishPlugins.bass) src;
      }
      {
        name = "fzf-fish";
        inherit (pkgs.fishPlugins.fzf-fish) src;
      }
      {
        name = "fifc";
        inherit (pkgs.fishPlugins.fifc) src;
      }
      {
        name = "kubectl-abbr";
        src = pkgs.fetchFromGitHub {
          owner = "lewisacidic";
          repo = "fish-kubectl-abbr";
          rev = "161450ab83da756c400459f4ba8e8861770d930c";
          sha256 = "sha256-iKNaD0E7IwiQZ+7pTrbPtrUcCJiTcVpb9ksVid1J6A0=";
        };
      }
      {
        name = "git-abbr";
        inherit (pkgs.fishPlugins.git-abbr) src;
      }
    ];
  };
}
# base00: "#1A1B26"
# base01: "#16161E"
# base02: "#2F3549"
# base03: "#444B6A"
# base04: "#787C99"
# base05: "#A9B1D6"
# base06: "#CBCCD1"
# base07: "#D5D6DB"
# base08: "#C0CAF5"
# base09: "#A9B1D6"
# base0A: "#0DB9D7"
# base0B: "#9ECE6A"
# base0C: "#B4F9F8"
# base0D: "#2AC3DE"
# base0E: "#BB9AF7"
# base0F: "#F7768E"

