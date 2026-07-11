{config, ...}: {
  flake.modules = {
    nixos.zsh = {pkgs, ...}: {
      programs.zsh.enable = true;
      users.users.${config.username}.shell = pkgs.zsh;
    };

    home.zsh = {
      pkgs,
      lib,
      config,
      ...
    }: let
      aliases = import ./_aliases.nix {};

      # Faithful stand-ins for the fish git-abbr / kubectl-abbr plugins:
      # inline-expanding abbreviations (type `gco` + space → `git checkout`).
      # Rendered into zsh-abbr's declarative user-abbreviations file below.
      abbreviations = {
        # git
        g = "git";
        ga = "git add";
        gaa = "git add --all";
        gb = "git branch";
        gc = "git commit -v";
        gcm = "git commit -m";
        gco = "git checkout";
        gcb = "git checkout -b";
        gd = "git diff";
        gds = "git diff --staged";
        gf = "git fetch";
        glg = "git log --oneline --graph --decorate";
        gl = "git pull";
        gp = "git push";
        grb = "git rebase";
        gs = "git status";
        gsw = "git switch";
        # kubectl
        kg = "kubectl get";
        kd = "kubectl describe";
        kaf = "kubectl apply -f";
        kdel = "kubectl delete";
        kl = "kubectl logs";
        klf = "kubectl logs -f";
        kex = "kubectl exec -it";
        kgp = "kubectl get pods";
        kgs = "kubectl get svc";
        kgn = "kubectl get nodes";
      };
      abbrFile =
        lib.concatStringsSep "\n"
        (lib.mapAttrsToList (k: v: "abbr ${k}='${v}'") abbreviations);
    in {
      # fzf shell integration (zsh equivalent of the former fzf-fish plugin);
      # provides fzf-tab's fzf backend and the ^T / ^R / ^G widgets.
      programs.fzf = {
        enable = true;
        enableZshIntegration = true;
        # Yield Ctrl-R to atuin (the fleet history manager, as under fish);
        # fzf keeps Ctrl-T (files) and Alt-C (dirs).
        historyWidget.command = "";
      };

      programs.zsh = {
        enable = true;
        # Lock the legacy ~/.zshrc location (the default flips to XDG at
        # stateVersion 26.05); keeps the `zshrc` alias (nvim ~/.zshrc) correct.
        dotDir = config.home.homeDirectory;
        shellAliases = aliases;
        enableCompletion = true;
        autosuggestion = {
          enable = true;
          highlight = "fg=#565f89"; # fish_color_autosuggestion
        };
        # base vi keybindings (fish had fish_vi_key_bindings); cursor shapes
        # are driven by the zle hook in initContent below.
        defaultKeymap = "viins";
        history = {
          size = 1000000;
          save = 1000000;
          ignoreDups = true;
        };
        # TokyoNight, mapped from the old fish_color_* palette.
        syntaxHighlighting = {
          enable = true;
          styles = {
            comment = "fg=#565f89";
            command = "fg=#7dcfff";
            builtin = "fg=#7dcfff";
            function = "fg=#7dcfff";
            "reserved-word" = "fg=#bb9af7";
            "single-quoted-argument" = "fg=#e0af68";
            "double-quoted-argument" = "fg=#e0af68";
            redirection = "fg=#c0caf5";
            "unknown-token" = "fg=#f7768e";
            path = "fg=#c0caf5";
          };
        };
        plugins = [
          {
            name = "zsh-abbr";
            src = pkgs.zsh-abbr;
            file = "share/zsh/zsh-abbr/zsh-abbr.plugin.zsh";
          }
          {
            name = "fzf-tab";
            src = pkgs.zsh-fzf-tab;
            file = "share/fzf-tab/fzf-tab.plugin.zsh";
          }
        ];

        initContent = ''
          ${pkgs.nix-your-shell}/bin/nix-your-shell zsh | source /dev/stdin

          export GOPATH="''${XDG_DATA_HOME:-$HOME/.local/share}/go"
          export GOPRIVATE="git.curve.tools,go.curve.tools,gitlab.com/imaginecurve"
          typeset -U path
          path+=("$HOME/.krew/bin" "$GOPATH/bin" /usr/local/bin /usr/bin "$HOME/.local/bin")

          # vi-mode cursor shapes: block in normal (vicmd), beam in insert.
          KEYTIMEOUT=1
          _zsh_cursor_shape() {
            case $KEYMAP in
              vicmd) printf '\e[2 q' ;;
              *)     printf '\e[6 q' ;;
            esac
          }
          zle -N zle-keymap-select _zsh_cursor_shape
          _zsh_cursor_init() { printf '\e[6 q'; }
          zle -N zle-line-init _zsh_cursor_init

          # ---- functions ported from the fish config ----
          envsource() {
            local line key val
            while IFS= read -r line; do
              [[ -z "$line" || "$line" == \#* ]] && continue
              key="''${line%%=*}"; val="''${line#*=}"
              export "$key=$val"
              echo "Exported key $key"
            done < "$1"
          }

          y() {
            local tmp cwd
            tmp="$(mktemp -t yazi-cwd.XXXXXX)"
            yazi "$@" --cwd-file="$tmp"
            if cwd="$(command cat -- "$tmp")" && [[ -n "$cwd" && "$cwd" != "$PWD" ]]; then
              builtin cd -- "$cwd"
            fi
            rm -f -- "$tmp"
          }

          gcrb() {
            local result
            result=$(git branch -a --color=always | grep -v '/HEAD\s' | sort |
              fzf --height 50% --border --ansi --tac --preview-window right:70% \
                --preview 'git log --oneline --graph --date=short --pretty="format:%C(auto)%cd %h%d %s" $(echo {} | sed "s/^..//" | cut -d" " -f1) | head -'"$LINES" |
              sed 's/^..//' | cut -d' ' -f1)
            [[ -z "$result" ]] && return
            if [[ "$result" == remotes/* ]]; then
              git checkout --track "''${result#remotes/}"
            else
              git checkout "$result"
            fi
          }

          hmg() {
            local current_gen
            current_gen=$(home-manager generations | head -n1 | awk '{print $7}')
            home-manager generations | awk '{print $7}' | tac |
              fzf --preview "echo {} | xargs -I % sh -c 'nvd --color=always diff $current_gen %' | xargs -I{} bash {}/activate"
          }

          rgvim() {
            rg --color=always --line-number --no-heading --smart-case "$@" |
              fzf --ansi \
                  --color "hl:-1:underline,hl+:-1:underline:reverse" \
                  --delimiter : \
                  --preview 'bat --color=always {1} --highlight-line {2}' \
                  --preview-window 'up,60%,border-bottom,+{2}+3/3,~3' \
                  --bind 'enter:become(nvim {1} +{2})'
          }

          # command-not-found: offer to run via comma (run-from-nixpkgs, with
          # a gum confirm and per-session memory), then fall back to nix-index's
          # nix-locate suggestion. Ported from fish (which composed both the
          # same way). We source + capture nix-index's handler here rather than
          # via programs.nix-index.enableZshIntegration so exactly one module
          # owns command_not_found_handler (no init-order race).
          source ${pkgs.nix-index}/etc/profile.d/command-not-found.sh
          functions[_cnf_nix_index]=$functions[command_not_found_handler]
          typeset -gA __comma_confirmed
          command_not_found_handler() {
            local cmd="$1"
            if [[ -n "''${__comma_confirmed[$cmd]}" ]] || ${pkgs.gum}/bin/gum confirm --selected.background=2 "Run using comma?"; then
              __comma_confirmed[$cmd]=1
              comma -- "$@"
              return $?
            fi
            if typeset -f _cnf_nix_index >/dev/null; then
              _cnf_nix_index "$@"
              return $?
            fi
            print -u2 "zsh: command not found: $cmd"
            return 127
          }
        '';
      };

      # zsh-abbr's declarative source of abbreviations (read-only; abbr add at
      # runtime replaces the symlink until the next switch restores it).
      home.sessionVariables.ABBR_USER_ABBREVIATIONS_FILE = "${config.home.homeDirectory}/.config/zsh-abbr/user-abbreviations";
      xdg.configFile."zsh-abbr/user-abbreviations".text = abbrFile + "\n";
    };
  };
}
