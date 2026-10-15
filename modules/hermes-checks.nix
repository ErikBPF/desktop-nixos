{inputs, ...}: let
  pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
  plugins = ./hosts/discovery/hermes-plugins;
  hermes = inputs.hermes-flake.packages.x86_64-linux.hermes-agent;
in {
  # Stdlib callbacks only: no official SDK, gateway, provider or live profile.
  flake.checks.x86_64-linux.hermes-plugin-selftests =
    pkgs.runCommand "hermes-plugin-selftests" {
      nativeBuildInputs = [pkgs.python3];
    } ''
      export HOME=$(mktemp -d) HERMES_HOME=$(mktemp -d) PYTHONDONTWRITEBYTECODE=1
      mkdir -p toolcall-leak-guard rtk-rewrite
      cp ${plugins + "/toolcall-leak-guard/__init__.py"} toolcall-leak-guard/__init__.py
      cp ${plugins + "/toolcall-leak-guard/selftest.py"} toolcall-leak-guard/selftest.py
      cp ${plugins + "/rtk-rewrite/__init__.py"} rtk-rewrite/__init__.py
      cp ${plugins + "/rtk-rewrite/selftest.py"} rtk-rewrite/selftest.py
      python3 -B toolcall-leak-guard/selftest.py
      python3 -B rtk-rewrite/selftest.py
      echo 'PASS hermes-plugin-selftests (stdlib callbacks only)' | tee "$out"
    '';

  # Installed SDK/finalizer with synthetic agent state, not provider/gateway E2E.
  flake.checks.x86_64-linux.hermes-plugin-native = pkgs.runCommand "hermes-plugin-native" {} ''
    export HOME=$(mktemp -d) HERMES_HOME=$(mktemp -d) PYTHONDONTWRITEBYTECODE=1
    export PYTHONNOUSERSITE=1
    mkdir -p toolcall-leak-guard
    cp ${plugins + "/toolcall-leak-guard/__init__.py"} toolcall-leak-guard/__init__.py
    cp ${plugins + "/toolcall-leak-guard/selftest.py"} toolcall-leak-guard/selftest.py
    cp ${plugins + "/toolcall-leak-guard/plugin.yaml"} toolcall-leak-guard/plugin.yaml
    # Reuse producer's real CLI/stamp check, not placeholder project metadata.
    ${hermes.venv}/bin/python -B ${inputs.hermes-flake}/tests/release-identity.py \
      ${hermes}/bin/hermes 0.21.7 71d34bad1045610252eda02ee79549436896e784
    ${hermes.venv}/bin/python -B toolcall-leak-guard/selftest.py \
      --native ${hermes.venv}/${hermes.python.sitePackages}
    echo 'PASS hermes-plugin-native (installed SDK/finalizer, synthetic state)' | tee "$out"
  '';

  # Real Restic with synthetic state; SSH and systemd intercepted by existing test.
  flake.checks.x86_64-linux.hermes-state-backup =
    pkgs.runCommand "hermes-state-backup" {
      nativeBuildInputs = [pkgs.python3 pkgs.restic pkgs.bash pkgs.coreutils pkgs.gnutar pkgs.just pkgs.jq];
    } ''
      export HOME=$(mktemp -d) HERMES_HOME=$(mktemp -d) PYTHONDONTWRITEBYTECODE=1
      mkdir -p tests scripts
      cp ${../tests/hermes-state-backup.py} tests/hermes-state-backup.py
      cp ${../scripts/hermes-state-backup.sh} scripts/hermes-state-backup.sh
      cp ${../justfile} justfile
      cp ${../fleet.json} fleet.json
      # Just recipes contain embedded shebangs; sandbox has no /usr/bin/env.
      substituteInPlace justfile --replace-fail '#!/usr/bin/env bash' '#!${pkgs.bash}/bin/bash'
      python3 -B tests/hermes-state-backup.py
      echo 'PASS hermes-state-backup (synthetic real-Restic check)' | tee "$out"
    '';
}
