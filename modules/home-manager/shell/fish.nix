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

        set -g fish_pager_color_secondary_background      4B5F6F --background normal     # Pager #4B5F6F
        set -g fish_pager_color_background                4B5F6F --background normal     # Pager #4B5F6F
        set -g fish_color_autosuggestion                  4B5F6F                         # Autosuggestions #4B5F6F
        set -g fish_color_command                         7FB4CA                         # Commands #7FB4CA
        set -g fish_color_comment                         4B5F6F                         # Code comments #4B5F6F
        set -g fish_color_cwd                             7AA89F                         # Current working directory #7AA89F
        set -g fish_color_end                             b6927b                         # Process separators #b6927b
        set -g fish_color_error                           E46876                         # Highlight potential errors #E46876
        set -g fish_color_escape                          8ea4a2                         # Character escapes #8ea4a2
        set -g fish_color_match                           938AA9                         # Matching parenthesis #938AA9
        set -g fish_color_normal                          A2A5A2                         # Default color #A2A5A2
        set -g fish_color_operator                        E6C384                         # Parameter expansion operators #E6C384
        set -g fish_color_param                           A2A5A2                         # Regular command parameters #A2A5A2
        set -g fish_color_quote                           87a987                         # Quoted blocks of text #87a987
        set -g fish_color_redirection                     a292a3                         # IO redirections #a292a3
        set -g fish_color_search_match                    4B5F6F --background E6C384     # Highlight search matches #E6C384 #4B5F6F
        set -g fish_color_selection                       4B5F6F --background E6C384     # Text selection #E6C384 #4B5F6F
        set -g fish_color_cancel                          0d0c0c                         # The '^C' indicator #0d0c0c
        set -g fish_color_host                            938AA9                         # Current host system #938AA9
        set -g fish_color_host_remote                     938AA9                         # Remote host system #938AA92
        set -g fish_color_user                            b98d7b                         # Current username #b98d7b



        set -g man_blink -o 2D4F67 #2D4F67
        set -g man_bold -o 87a987 #87a987
        set -g man_standout -b black 93a1a1 #93a1a1
        set -g man_underline -u 93a1a1 #93a1a1
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
