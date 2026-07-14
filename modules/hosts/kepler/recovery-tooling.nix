{lib, ...}: {
  flake.modules.nixos.kepler-recovery-tooling = {pkgs, ...}: let
    planner = pkgs.writeTextFile {
      name = "kepler-collision-recovery-plan";
      destination = "/bin/kepler-collision-recovery-plan";
      executable = true;
      text =
        builtins.replaceStrings
        ["#!/usr/bin/env python3"]
        ["#!${pkgs.python3}/bin/python3"]
        (builtins.readFile ./_collision_recovery_planner.py);
    };
  in {
    assertions = [
      {
        assertion = lib.getVersion pkgs.secretspec == "0.13.0";
        message = "Kepler recovery requires the reviewed SecretSpec 0.13.0 pin";
      }
    ];

    environment.systemPackages = [
      pkgs.secretspec
      planner
    ];
  };
}
