{...}: {
  flake.modules.nixos.openssh = {...}: {
    services.openssh = {
      enable = true;
      openFirewall = true;
      ports = [2222];
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
      };
    };
  };
}
