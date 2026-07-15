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
    executor = pkgs.writeShellApplication {
      name = "kepler-collision-recovery-executor";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.podman
        pkgs.postgresql
        pkgs.python3
      ];
      text = builtins.readFile ./_collision_recovery_executor.sh;
    };
    postgresEvidence = pkgs.writeShellApplication {
      name = "kepler-collision-postgres-evidence";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.gnutar
        pkgs.podman
        pkgs.python3
      ];
      text = builtins.readFile ./_collision_recovery_postgres_evidence.sh;
    };
    redisEvidence = pkgs.writeShellApplication {
      name = "kepler-collision-redis-evidence";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.podman
        pkgs.python3
      ];
      text = builtins.readFile ./_collision_recovery_redis_evidence.sh;
    };
    evidenceJob = pkgs.writeShellApplication {
      name = "kepler-collision-evidence-job";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.python3
        pkgs.systemd
        pkgs.util-linux
        postgresEvidence
        redisEvidence
      ];
      text = builtins.readFile ./_collision_recovery_evidence_job.sh;
    };
    retirementJob = pkgs.writeShellApplication {
      name = "kepler-collision-retirement-job";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.python3
        pkgs.systemd
        pkgs.util-linux
        executor
      ];
      text = builtins.readFile ./_collision_recovery_retirement_job.sh;
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
      executor
      planner
      postgresEvidence
      redisEvidence
      evidenceJob
      retirementJob
    ];

    systemd.user.services."kepler-collision-evidence@" = {
      description = "Kepler collision recovery evidence job %i";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${evidenceJob}/bin/kepler-collision-evidence-job execute %i";
        UMask = "0077";
        TimeoutStartSec = "infinity";
        KillMode = "control-group";
      };
    };

    systemd.user.services."kepler-collision-retirement@" = {
      description = "Kepler collision recovery retirement job %i";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${retirementJob}/bin/kepler-collision-retirement-job execute %i";
        UMask = "0077";
        TimeoutStartSec = "infinity";
        KillMode = "control-group";
      };
    };
  };
}
