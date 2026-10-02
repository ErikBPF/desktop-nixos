#!/usr/bin/env bash
set -euo pipefail
# Evaluate actual guest boot configuration and shared stop-propagation guards.
nix eval --offline --json .#nixosConfigurations.kepler.config --apply 'c:
  assert builtins.attrNames c.microvm.vms == ["cp-1" "cp-2" "cp-3" "w-1" "w-2" "w-3"];
  assert !(builtins.elem "clocksource=kvm-clock" c.boot.kernelParams);
  assert builtins.all (vm: !vm.restartIfChanged && builtins.elem "clocksource=kvm-clock" vm.config.config.boot.kernelParams) (builtins.attrValues c.microvm.vms);
  assert builtins.all (n: !c.systemd.services.${n}.restartIfChanged) [
    "harbor-reader" "k3s-bootstrap-materialize" "k3s-cluster-token"
    "zfs-import-fast-pool" "zfs-import-bulk-pool"
  ]; true'
