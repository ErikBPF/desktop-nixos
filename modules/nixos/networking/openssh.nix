{...}: {
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      X11Forwarding = false;
      AllowTcpForwarding = "no";
      ClientAliveCountMax = 2;
      MaxAuthTries = 3;
      MaxSessions = 2;
      TCPKeepAlive = "no";
      AllowAgentForwarding = "no";
      Port = 2222; 
    };
  };
}
