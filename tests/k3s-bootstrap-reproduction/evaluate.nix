let
  flake = builtins.getFlake (toString ../..);
  config = flake.nixosConfigurations.kepler.config;
  guests = config.microvm.vms;
  cp1 = guests.cp-1.config.config;
in
  assert cp1.services.k3s.package.version == "1.36.5+k3s1";
  assert !cp1.services.k3s.clusterInit;
  assert cp1.services.k3s.serverAddr == "https://10.250.0.13:6443";
  assert cp1.services.k3s.tokenFile == "/tokens/token";
  assert cp1.systemd.services.k3s.wantedBy == [];
  assert cp1.systemd.services.k3s.serviceConfig.Restart == "no";
  assert cp1.systemd.services.k3s.serviceConfig.TimeoutStartSec == "5min";
  assert !cp1.systemd.services.k3s-bootstrap-secrets.enable;
  assert !cp1.systemd.timers.k3s-bootstrap-secrets.enable;
  assert builtins.all (name: !guests.${name}.restartIfChanged) (builtins.attrNames guests);
  assert guests.cp-2.config.config.services.k3s.serverAddr == "https://10.250.0.1:6443";
  assert guests.cp-3.config.config.services.k3s.serverAddr == "https://10.250.0.1:6443"; "CP1_MEMBER_REPLACEMENT_CANDIDATE_OK"
