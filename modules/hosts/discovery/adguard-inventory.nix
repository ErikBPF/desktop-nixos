# Value-free AdGuard inventory collector, retained after the P2 migration.
#
# The stateful-migration tooling was deleted with the finished phases, but
# `just discovery-adguard-exporter-diagnostic` survives as an incident
# diagnostic: it reads the exporter's own metric-family names and never prints
# values. This module keeps the one binary that recipe runs.
_: {
  flake.modules.nixos.discovery-adguard-inventory = {pkgs, ...}: {
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "discovery-stateful-adguard-inventory" ''
        exec ${pkgs.python3}/bin/python3 ${./_stateful-adguard-inventory.py} "$@"
      '')
    ];
  };
}
