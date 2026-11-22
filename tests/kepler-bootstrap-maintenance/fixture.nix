let
  flake = builtins.getFlake (toString ../..);
  guest = flake.nixosConfigurations.kepler.config.microvm.vms.cp-1.config.config;
  unit = guest.systemd.services.k3s-bootstrap-secrets;
  manifest = guest.systemd.services.k3s-manifest-reconcile;
in {
  inherit (unit) wants after wantedBy;
  condition = unit.serviceConfig.ExecCondition or "";
  timer = guest.systemd.timers.k3s-bootstrap-secrets.timerConfig;
  k3sWantedBy = guest.systemd.services.k3s.wantedBy;
  manifest = {
    inherit (manifest) wants after wantedBy;
    condition = manifest.serviceConfig.ExecCondition or "";
    remainAfterExit = manifest.serviceConfig.RemainAfterExit;
  };
}
