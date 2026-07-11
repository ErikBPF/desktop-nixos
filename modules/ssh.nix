_: {
  flake.modules.home.ssh = _: {
    home.file.".ssh/ro_config" = {
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

        # Fleet hosts: resolve via tailnet MagicDNS (no LAN HostName override).
        # sshd is fleet-wide on port 2222 (modules/networking/openssh.nix).
        Host orion 192.168.10.220
          Port 2222
          User erik

        Host kepler
          Port 2222
          User erik

        Host archinaut
          Port 2222
          User erik

        Host pathfinder
          Port 2222
          User erik

        Host voyager
          Port 2222
          User erik
      '';
      onChange = ''
        cp ~/.ssh/ro_config ~/.ssh/config
        chmod 0400 ~/.ssh/config
      '';
    };
  };
}
