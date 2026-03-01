{...}: {
  networking.firewall = {
    enable = true;
    allowPing = false; # Optional: drop ICMP ping
  };
  services.fail2ban = {
    enable = true;
    maxretry = 3;
    bantime = "1h";
    bantime-increment.enable = true;
  };
}
