{pkgs, ...}: let
  aliases = import ./aliases.nix {};
in {
  programs.fish = {
      enable = true;
      interactiveShellInit = ''
        ${pkgs.nix-your-shell}/bin/nix-your-shell --nom fish | source
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

        set -g fish_pager_color_secondary_background      2F3549 --background normal     # Pager #2F3549
        set -g fish_pager_color_background                2F3549 --background normal     # Pager #2F3549
        set -g fish_color_autosuggestion                  787C99                         # Autosuggestions #787C99
        set -g fish_color_command                         9ECE6A                         # Commands #9ECE6A
        set -g fish_color_comment                         444B6A                         # Code comments #444B6A
        set -g fish_color_cwd                             2AC3DE                         # Current working directory #2AC3DE
        set -g fish_color_end                             F7768E                         # Process separators #F7768E
        set -g fish_color_error                           C0CAF5                         # Highlight potential errors #C0CAF5
        set -g fish_color_escape                          B4F9F8                         # Character escapes #B4F9F8
        set -g fish_color_match                           0DB9D7                         # Matching parenthesis #0DB9D7
        set -g fish_color_normal                          A9B1D6                         # Default color #A9B1D6
        set -g fish_color_operator                        BB9AF7                         # Parameter expansion operators #BB9AF7
        set -g fish_color_param                           A9B1D6                         # Regular command parameters #A9B1D6
        set -g fish_color_quote                           9ECE6A                         # Quoted blocks of text #9ECE6A
        set -g fish_color_redirection                     B4F9F8                         # IO redirections #B4F9F8
        set -g fish_color_search_match                    0DB9D7 --background 16161E     # Highlight search matches #0DB9D7 #16161E
        set -g fish_color_selection                       0DB9D7 --background 16161E     # Text selection #0DB9D7 #16161E
        set -g fish_color_cancel                          C0CAF5                         # The '^C' indicator #C0CAF5
        set -g fish_color_host                            2AC3DE                         # Current host system #2AC3DE
        set -g fish_color_host_remote                     2AC3DE                         # Remote host system #2AC3DE
        set -g fish_color_user                            9ECE6A                         # Current username #9ECE6A



        set -g man_blink -o 444B6A #444B6A
        set -g man_bold -o 9ECE6A #9ECE6A
        set -g man_standout -b black B4F9F8 #B4F9F8
        set -g man_underline -u B4F9F8 #B4F9F8
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
