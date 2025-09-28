{
  inputs,
  pkgs,
  ...
}: {
  users.users = {
    erik = {
      isNormalUser = true;
      initialPassword = "1045";
      shell = pkgs.fish;
      openssh.authorizedKeys.keys = [
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

  environment.etc = {
    "/home/erik/.ssh/config" = {
      text = ''
        Host *
          ForwardAgent no
          AddKeysToAgent no
          Compression no
          ServerAliveInterval 0
          ServerAliveCountMax 3
          HashKnownHosts no
          UserKnownHostsFile ~/.ssh/known_hosts
          ControlMaster no
          ControlPath ~/.ssh/master-%r@%n:%p
          ControlPersist no
          SetEnv TERM=xterm-256color

        Host github_erikbpf
          HostName github.com
          User git
          IdentityFile ~/.ssh/id_ed25519

        Host github_nstech
          HostName github.com
          User git
          IdentityFile ~/.ssh/id_rsa
      '';
      mode = "0400";
    };
  };
  programs.fish.enable = true;
}
