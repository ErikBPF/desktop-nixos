_: {
  flake.modules.nixos.firewall = {config, ...}: {
    networking.firewall = {
      enable = true;
      allowPing = false;
    };
    services.fail2ban = {
      enable = true;
      maxretry = 3;
      bantime = "1h";
      bantime-increment.enable = true;
      jails.sshd.settings.journalmatch = "_SYSTEMD_UNIT=sshd.service + _COMM=sshd + _COMM=sshd-session";
    };
    systemd.services.fail2ban.environment.LD_LIBRARY_PATH = "${config.systemd.package}/lib";
  };
}
