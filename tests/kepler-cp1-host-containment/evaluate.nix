let
  f = builtins.getFlake (toString ../..);
  baseline = (builtins.getFlake "github:ErikBPF/desktop-nixos/030d17cf4f9d56a40a3205d4af2ae7867a208e7d").nixosConfigurations.kepler.config;
  repaired = (builtins.getFlake "github:ErikBPF/desktop-nixos/a3f290e015eacce61e718f8596cdb6acc3716c7c").nixosConfigurations.kepler.config;
  c = f.nixosConfigurations.kepler-cp1-recovery.config;
  vm = c.microvm.vms.cp-1;
  guest =
    if vm.evaluatedConfig != null
    then vm.evaluatedConfig.config
    else vm.config.config;
  runner = guest.microvm.declaredRunner.outPath;
  installer = c.systemd.services.install-microvm-cp-1;
  unitDelta = a: z: builtins.filter (n: (a.systemd.units.${n}.text or null) != (z.systemd.units.${n}.text or null)) (builtins.attrNames (a.systemd.units // z.systemd.units));
  node = f.deploy.nodes.kepler-cp1-recovery;
  normalNode = f.deploy.nodes.kepler;
  expectedEncryptedFileSha256 = "4677ac8136bb743b1d01603d7d50446efdbf3347e915af8dd90972dfeb51f96d";
  contains = needle: f.inputs.nixpkgs.lib.hasInfix (builtins.unsafeDiscardStringContext needle);
in
  assert baseline.system.build.toplevel.outPath == "/nix/store/zi7mrrickfv7haaglmy7yrsljr9zgk9p-nixos-system-kepler-26.11.20261115.5c3cda7";
  assert runner == "/nix/store/s226dm43kyklikzpbg64aj1vwhlgydhb-microvm-cloud-hypervisor-cp-1";
  assert contains "ln -sTf ${runner} current" installer.script;
  assert builtins.elem "microvm@cp-1.service" installer.before;
  assert builtins.elem "microvms.target" installer.wantedBy;
  assert guest.systemd.services.k3s.wantedBy == [];
  assert !guest.services.k3s.clusterInit;
  assert guest.services.k3s.serverAddr == "https://10.250.0.13:6443";
  assert !guest.systemd.services.k3s-bootstrap-secrets.enable;
  assert !guest.systemd.timers.k3s-bootstrap-secrets.enable;
  assert !vm.restartIfChanged;
  assert !c.system.autoUpgrade.enable;
  assert !c.boot.loader.systemd-boot.bootCounting.enable;
  assert builtins.all (n: baseline.microvm.vms.${n}.config.config.microvm.declaredRunner.outPath == c.microvm.vms.${n}.config.config.microvm.declaredRunner.outPath) ["cp-2" "cp-3" "w-1" "w-2" "w-3"];
  assert unitDelta baseline repaired == ["home-manager-erik.service"];
  assert unitDelta repaired c == ["install-microvm-cp-1.service" "microvm@cp-1.service"];
  assert builtins.hashFile "sha256" c.sops.secrets.openbao-harbor-reader-kepler-secret-id.sopsFile == expectedEncryptedFileSha256;
  assert builtins.removeAttrs node ["profiles"] == builtins.removeAttrs normalNode ["profiles"];
  assert builtins.removeAttrs node.profiles ["system"] == builtins.removeAttrs normalNode.profiles ["system"];
  assert builtins.removeAttrs node.profiles.system ["path"] == builtins.removeAttrs normalNode.profiles.system ["path"];
  assert node.profiles.system.path != normalNode.profiles.system.path; "KEPLER_DURABLE_CP1_BOOT_OK ${c.system.build.toplevel.outPath} ${node.profiles.system.path}"
