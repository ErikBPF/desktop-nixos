{...}: {
  services.logrotate = {
    enable = true;
    # settings = {
    #   "/var/log/omnixy/*.log" = {
    #     frequency = "weekly";
    #     rotate = 4;
    #     compress = true;
    #     delaycompress = true;
    #     notifempty = true;
    #     create = "644 root root";
    #   };
    # };
  };
}
