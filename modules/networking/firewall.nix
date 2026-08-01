_: {
  flake.modules.nixos.firewall = _: {
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
  };
}
