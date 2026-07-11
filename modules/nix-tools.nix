_: {
  flake.modules.home.nix-tools = {pkgs, ...}: {
    programs.nix-index = {
      enable = true;
      # zsh's command_not_found_handler is owned by modules/shell/zsh.nix
      # (it wraps this same script with a comma prompt); leaving this on would
      # make two modules define the handler and race on init order.
      enableZshIntegration = false;
    };

    systemd.user.services.nix-index-update = {
      Unit = {
        Description = "Update nix-index database";
        After = ["network-online.target"];
        Wants = ["network-online.target"];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${pkgs.nix-index}/bin/nix-index";
        Nice = 19;
        IOSchedulingClass = "idle";
      };
    };

    systemd.user.timers.nix-index-update = {
      Unit.Description = "Update nix-index database every Sunday at 4 AM";
      Timer = {
        OnCalendar = "Sun *-*-* 04:00:00";
        Persistent = true;
      };
      Install.WantedBy = ["timers.target"];
    };
  };
}
