_: {
  flake.modules.home.kindle-auto-eject = {pkgs, ...}: let
    eject = pkgs.writeShellApplication {
      name = "kindle-auto-eject";
      runtimeInputs = [pkgs.python3 pkgs.util-linux pkgs.udisks2 pkgs.systemd];
      text = ''exec python3 ${./_kindle-auto-eject.py}'';
    };
  in {
    home.file.".local/bin/kindle-auto-eject".source = "${eject}/bin/kindle-auto-eject";

    systemd.user.services.kindle-auto-eject = {
      Unit.Description = "Safely eject Kindle USB storage";
      Service = {
        Type = "oneshot";
        ExecStart = "${eject}/bin/kindle-auto-eject";
        TimeoutStartSec = 30;
      };
    };

    systemd.user.timers.kindle-auto-eject = {
      Unit.Description = "Check for Kindle USB storage every five seconds";
      Timer = {
        OnStartupSec = 5;
        OnUnitInactiveSec = 5;
        AccuracySec = 1;
      };
      Install.WantedBy = ["timers.target"];
    };
  };
}
