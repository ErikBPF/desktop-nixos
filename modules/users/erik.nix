{inputs, ...}: {
  users.users = {
    erik = {
      isNormalUser = true;
      initialPassword = "1045";
      openssh.authorizedKeys.keys =
  [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMxdE+uAvR4Nm2XwZNjTf2Ae8PlrRtnZUI6BBrbGl78u erikbogado@gmail.com"
  ];

      extraGroups = [
        "audio"
        "input"
        "networkmanager"
        "sound"
        "tty"
        "wheel"
        "docker"
        "qemu"
        "kvm"
        "libvirtd"
      ];
    };
  };
}
