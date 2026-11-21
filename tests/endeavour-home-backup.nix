let
  flake = builtins.getFlake (toString ../.);
  cfg = flake.nixosConfigurations.endeavour.config;
  backup = cfg.services.restic.backups.endeavour-home;
  service = cfg.systemd.services.restic-backups-endeavour-home.serviceConfig;
in
  assert backup.paths == ["/home/erik"];
  assert backup.exclude == ["/home/erik/.gvfs"];
  assert !(builtins.elem "--one-file-system" backup.extraBackupArgs);
  assert !(builtins.elem 3 (service.SuccessExitStatus or []));
  assert !(builtins.elem "3" (service.SuccessExitStatus or [])); "ENDEAVOUR_BACKUP_GVFS_OK"
