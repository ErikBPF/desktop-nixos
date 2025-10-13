{
  config,
  pkgs,
  ...
}: {
  services.fail2ban = {
    enable = true;
    maxretry = 3;
    bantime = "1h";
    bantime-increment.enable = true;
  };
}
