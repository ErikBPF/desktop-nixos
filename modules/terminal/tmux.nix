_: {
  # General-purpose multiplexer for plain SSH / non-herdr sessions (herdr owns
  # the AI-agent panes). Base16 theming comes from the stylix tmux target,
  # enabled centrally in modules/desktop/stylix.nix so this module stays
  # portable to hosts without stylix (e.g. the orion dev-sandbox microvm).
  # Session save/restore is intentionally omitted: herdr already provides
  # session persistence, so no resurrect/continuum here.
  flake.modules.home.tmux = {pkgs, ...}: {
    home.packages = [
      (pkgs.writeShellApplication {
        name = "tmux-repo";
        runtimeInputs = [pkgs.git pkgs.ncurses pkgs.tmux];
        text = ''
          repo=$(git -C "''${1:-.}" rev-parse --show-toplevel)
          session=''${repo##*/}

          if tmux has-session -t "=$session" 2>/dev/null &&
            [[ $(tmux display-message -p -t "=$session:1" '#{window_panes}') != 7 ]]; then
            tmux kill-session -t "=$session"
          fi

          if ! tmux has-session -t "=$session" 2>/dev/null; then
            left_top=$(tmux new-session -d -P -F '#{pane_id}' -s "$session" -n "$session" -c "$repo" "codex --yolo; exec ${pkgs.zsh}/bin/zsh")
            tmux set-option -w -t "=$session:1" remain-on-exit on
            right_top=$(tmux split-window -h -p 50 -P -F '#{pane_id}' -t "$left_top" -c "$repo" nvim)
            middle_top=$(tmux split-window -h -p 50 -P -F '#{pane_id}' -t "$left_top" -c "$repo" "codex --yolo; exec ${pkgs.zsh}/bin/zsh")
            tmux split-window -v -p 50 -t "$left_top" -c "$repo" "codex --yolo; exec ${pkgs.zsh}/bin/zsh"
            tmux split-window -v -p 50 -t "$middle_top" -c "$repo" "codex --yolo; exec ${pkgs.zsh}/bin/zsh"
            right_bottom=$(tmux split-window -v -p 50 -P -F '#{pane_id}' -t "$right_top" -c "$repo")
            tmux split-window -h -p 50 -t "$right_bottom" -c "$repo"
            tmux select-pane -t "$right_top"
          fi

          for pane in 1 2 3 4; do
            if [[ $(tmux display-message -p -t "=$session:1.$pane" '#{pane_dead}') == 1 ]]; then
              tmux respawn-pane -k -t "=$session:1.$pane" -c "$repo" "codex --yolo; exec ${pkgs.zsh}/bin/zsh"
            fi
          done
          if [[ $(tmux display-message -p -t "=$session:1.5" '#{pane_dead}') == 1 ]]; then
            tmux respawn-pane -k -t "=$session:1.5" -c "$repo" nvim
          fi
          for pane in 6 7; do
            if [[ $(tmux display-message -p -t "=$session:1.$pane" '#{pane_dead}') == 1 ]]; then
              tmux respawn-pane -k -t "=$session:1.$pane" -c "$repo"
            fi
          done

          if [[ -n "''${TMUX:-}" ]]; then
            columns=$(tmux display-message -p '#{client_width}')
            lines=$(tmux display-message -p '#{client_height}')
          else
            columns=$(tput cols)
            lines=$(tput lines)
          fi
          slot=$(((columns - 3) / 4))
          tmux resize-window -t "=$session:1" -x "$columns" -y "$lines"
          tmux resize-pane -t "=$session:1.5" -x "$((columns - 2 * (slot + 1)))"
          tmux resize-pane -t "=$session:1.7" -x "$slot"
          tmux resize-pane -t "=$session:1.1" -x "$slot"

          if [[ -n "''${TMUX:-}" ]]; then
            exec tmux switch-client -t "=$session"
          else
            exec tmux attach-session -t "=$session"
          fi
        '';
      })
    ];

    programs.tmux = {
      enable = true;
      shell = "${pkgs.zsh}/bin/zsh";
      keyMode = "vi";
      mouse = true;
      baseIndex = 1;
      escapeTime = 10;
      historyLimit = 50000;
      terminal = "tmux-256color";
      extraConfig = ''
        # Pass 24-bit truecolor through from the outer terminal so
        # zsh-syntax-highlighting's fg=#hex styles render inside tmux.
        set -ga terminal-features "*:RGB"
      '';
      plugins = with pkgs.tmuxPlugins; [
        sensible
        vim-tmux-navigator
        yank
      ];
    };
  };
}
