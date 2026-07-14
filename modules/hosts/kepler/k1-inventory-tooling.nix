_: {
  flake.modules.nixos.kepler-k1-inventory-tooling = {pkgs, ...}: let
    inventory = pkgs.writeTextFile {
      name = "kepler-collision-recovery-inventory";
      destination = "/bin/kepler-collision-recovery-inventory";
      executable = true;
      text =
        builtins.replaceStrings
        ["#!/usr/bin/env python3"]
        ["#!${pkgs.python3}/bin/python3"]
        (builtins.readFile ./_collision_recovery_inventory.py);
    };
  in {
    environment.systemPackages = [inventory];
  };
}
