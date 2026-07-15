{self, ...}: {
  flake.modules.nixos.endeavour-home-backup = {config, ...}: {
    sops.secrets = {
      restic_tofu_state_password.sopsFile = self + "/secrets/sops/secrets.yaml";
      restic_offsite_ssh_key = {
        sopsFile = self + "/secrets/sops/secrets.yaml";
        mode = "0400";
      };
    };

    programs.ssh.extraConfig = ''
      Host restic-kepler
        HostName kepler
        Port 2222
        User restic-offsite
        IdentityFile ${config.sops.secrets.restic_offsite_ssh_key.path}
        IdentitiesOnly yes
        StrictHostKeyChecking accept-new
        UserKnownHostsFile /root/.ssh/known_hosts
    '';

    systemd.tmpfiles.rules = ["d /root/.ssh 0700 root root - -"];

    services.restic.backups.endeavour-home = {
      repository = "sftp:restic-kepler:/bulk/backups/restic-offsite/endeavour-home";
      passwordFile = config.sops.secrets.restic_tofu_state_password.path;
      paths = ["/home/erik"];
      initialize = true;
      timerConfig = {
        OnCalendar = "*-*-* 02:00:00";
        Persistent = true;
        RandomizedDelaySec = "30m";
      };
      pruneOpts = [
        "--keep-daily 7"
        "--keep-weekly 4"
        "--keep-monthly 6"
      ];
    };
  };
}
