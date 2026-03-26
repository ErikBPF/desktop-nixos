{...}: {
  services.atuin = {
    enable = true;
    # Optional: Configure a server for sync (uncomment and configure if needed)
    # server = {
    #   enable = true;
    #   host = "0.0.0.0";
    #   port = 8888;
    # };
  };
}
