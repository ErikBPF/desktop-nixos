{
  baselineUrl,
  recoveryUrl,
}: let
  base = (builtins.getFlake baselineUrl).nixosConfigurations.kepler;
  guest = (builtins.getFlake recoveryUrl).nixosConfigurations.kepler.config.microvm.vms.cp-1.config;
  updated = base.extendModules {modules = [{microvm.vms.cp-1.evaluatedConfig = guest;}];};
  extract = host: g: {
    installer = host.config.systemd.services.install-microvm-cp-1.script;
    remainAfterExit = host.config.systemd.services.install-microvm-cp-1.serviceConfig.RemainAfterExit or false;
    before = host.config.systemd.services.install-microvm-cp-1.before;
    partOf = host.config.systemd.services.install-microvm-cp-1.partOf;
    wantedBy = host.config.systemd.services.install-microvm-cp-1.wantedBy;
    runner = g.config.microvm.declaredRunner.outPath;
    k3sWantedBy = g.config.systemd.services.k3s.wantedBy;
    clusterInit = g.config.services.k3s.clusterInit;
    serverAddr = g.config.services.k3s.serverAddr;
  };
in {
  baseline = extract base base.config.microvm.vms.cp-1.config;
  candidate = extract updated guest;
  baselineSystem = base.config.system.build.toplevel.outPath;
  restartIfChanged = updated.config.microvm.vms.cp-1.restartIfChanged;
}
