let
  flake = builtins.getFlake (toString ../..);
  guest = flake.nixosConfigurations.kepler.config.microvm.vms.cp-1.config.config;
  unit = guest.systemd.services.k3s-bootstrap-secrets;
in {
  inherit (unit) wants after wantedBy;
  condition = unit.serviceConfig.ExecCondition or "";
  timer = guest.systemd.timers.k3s-bootstrap-secrets.timerConfig;
}
