{inputs, ...}: {
  users.users = {
    henry = {
      isNormalUser = true;
      initialPassword = "1045";
      openssh.authorizedKeys.keys =
  [
    # change this to your ssh key
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMxdE+uAvR4Nm2XwZNjTf2Ae8PlrRtnZUI6BBrbGl78u erikbogado@gmail.com"
  ] ++ (args.extraPublicKeys or []);

      extraGroups = [
        "audio"
        "input"
        "networkmanager"
        "sound"
        "tty"
        "wheel"
        "docker"
      ];
    };
  };
}
