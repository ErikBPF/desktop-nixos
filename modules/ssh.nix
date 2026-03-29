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
      '';
      onChange = ''
        cp ~/.ssh/ro_config ~/.ssh/config
        chmod 0400 ~/.ssh/config
      '';
    };
  };
}
