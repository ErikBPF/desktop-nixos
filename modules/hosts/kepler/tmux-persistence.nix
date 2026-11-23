{config, ...}: let
  flakeConfig = config;
in {
  flake.modules.nixos.kepler-tmux-persistence = {pkgs, ...}: let
    home = "/home/${flakeConfig.username}";
    servicePath = "/run/wrappers/bin:${home}/.nix-profile/bin:/run/current-system/sw/bin";
    resurrect = "${pkgs.tmuxPlugins.resurrect}/share/tmux-plugins/resurrect";
    resurrectDir = "${home}/.local/share/tmux/resurrect-kepler";
    restore = pkgs.writeShellScript "kepler-tmux-restore" ''
      for _ in $(${pkgs.coreutils}/bin/seq 1 40); do
        ${pkgs.tmux}/bin/tmux -N show-options -s exit-empty >/dev/null 2>&1 && break
        ${pkgs.coreutils}/bin/sleep 0.1
      done
      ${pkgs.tmux}/bin/tmux -N run-shell ${resurrect}/scripts/restore.sh
    '';
  in {
    # Kepler's default tmux server is the one sk/tmux-resume uses. The NixOS
    # tmux module's secureSocket default exports TMUX_TMPDIR through
    # /etc/set-environment, so `%t` in this unit is the same runtime directory
    # the SSH clients resolve. Keep the server alive without clients and
    # restore the last snapshot before a client lists sessions.
    programs.tmux = {
      plugins = [pkgs.tmuxPlugins.resurrect];
      extraConfig = ''
        set -g exit-empty off
        set -g destroy-unattached off
        set -g @resurrect-dir "${resurrectDir}"
        set -g @resurrect-processes '"nvim->nvim" ssh'
      '';
    };

    systemd.user.services.kepler-tmux = {
      description = "Persistent Kepler tmux server";
      wantedBy = ["default.target"];
      serviceConfig = {
        # A live tmux server means a client or an earlier boot already owns
        # the socket; skip the unit instead of fighting it. Probe the server,
        # not sessions: this module keeps a sessionless server alive.
        ExecCondition = "${pkgs.bash}/bin/bash -c '! ${pkgs.tmux}/bin/tmux -N list-sessions >/dev/null 2>&1'";
        ExecStart = "${pkgs.tmux}/bin/tmux -D";
        ExecStartPost = "-${restore}";
        ExecStop = "-${pkgs.tmux}/bin/tmux -N run-shell ${resurrect}/scripts/save.sh";
        Environment = [
          "TMUX_TMPDIR=%t"
          "PATH=${servicePath}"
        ];
        Restart = "on-failure";
        RestartSec = 2;
      };
    };

    systemd.user.services.kepler-tmux-save = {
      description = "Save Kepler tmux session state";
      serviceConfig = {
        Type = "oneshot";
        ExecCondition = "${pkgs.tmux}/bin/tmux -N has-session";
        ExecStart = "${pkgs.tmux}/bin/tmux -N run-shell ${resurrect}/scripts/save.sh";
        Environment = [
          "TMUX_TMPDIR=%t"
          "PATH=${servicePath}"
        ];
      };
    };

    systemd.user.timers.kepler-tmux-save = {
      description = "Periodically save Kepler tmux session state";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnStartupSec = "5min";
        OnUnitActiveSec = "5min";
        Unit = "kepler-tmux-save.service";
      };
    };
  };
}
