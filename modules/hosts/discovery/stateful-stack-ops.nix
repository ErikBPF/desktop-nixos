_: {
  flake.modules.nixos.discovery-stateful-stack-ops = {pkgs, ...}: let
    statefulStackOps = pkgs.writeShellApplication {
      name = "discovery-stateful-stack-ops";
      runtimeInputs = with pkgs; [
        bind
        btrfs-progs
        coreutils
        curl
        docker
        findutils
        gawk
        git
        gnugrep
        gnutar
        jq
        rsync
        systemd
        zstd
      ];
      text = builtins.readFile ./_stateful-stack-ops.sh;
    };
    statefulStackFixture = pkgs.writeShellApplication {
      name = "discovery-stateful-stack-fixture";
      runtimeInputs = with pkgs; [
        acl
        attr
        coreutils
        docker
        git
        jq
        statefulStackOps
      ];
      text = builtins.readFile ./_stateful-stack-fixture.sh;
    };
    statefulSwagAdopt = pkgs.writeShellApplication {
      name = "discovery-stateful-swag-adopt";
      runtimeInputs = with pkgs; [
        btrfs-progs
        coreutils
        curl
        docker
        docker-compose
        gawk
        gnugrep
        jq
        openssl
        statefulStackOps
        statefulSwagInventory
        statefulSwagPreflight
        util-linux
      ];
      text = builtins.readFile ./_stateful-swag-adopt.sh;
    };
    statefulSwagInventory = pkgs.writeShellScriptBin "discovery-stateful-swag-inventory" ''
      exec ${pkgs.python3}/bin/python3 ${./_stateful-swag-inventory.py} "$@"
    '';
    statefulSwagPreflight = pkgs.writeShellScriptBin "discovery-stateful-swag-preflight" ''
      exec ${pkgs.python3}/bin/python3 ${./_stateful-swag-preflight.py} "$@"
    '';
    statefulAdguardInventory = pkgs.writeShellScriptBin "discovery-stateful-adguard-inventory" ''
      exec ${pkgs.python3}/bin/python3 ${./_stateful-adguard-inventory.py} "$@"
    '';
    statefulAdguardPreflight = pkgs.writeShellScriptBin "discovery-stateful-adguard-preflight" ''
      export P2_ADGUARD_TARGET_COMMIT=9969e35dca0cfb49a68bda3ba10156667cd4b53f
      export P2_ADGUARD_IMAGE_ADGUARD=adguard/adguardhome:v0.108.0-b.83@sha256:8399ec9bdcb76d5ef4f217ed2d0272dc9f3fb283eb2613744610988232d91927
      export P2_ADGUARD_IMAGE_EXPORTER=ghcr.io/henrywhitaker3/adguard-exporter:v1.2.1@sha256:42a9581bae4a91e6d4985415d1fe89ab9b1f50fbe2945a1c122d212d6354b747
      exec ${pkgs.python3}/bin/python3 ${./_stateful-adguard-preflight.py} "$@"
    '';
    statefulAdguardPostcheck = pkgs.writeShellApplication {
      name = "discovery-stateful-adguard-postcheck";
      runtimeInputs = with pkgs; [
        docker
        python3
        statefulAdguardInventory
      ];
      text = ''
        exec python3 ${./_stateful-adguard-postcheck.py} "$@"
      '';
    };
    servarrExactRevision = pkgs.writeShellApplication {
      name = "servarr-exact-revision";
      runtimeInputs = with pkgs; [docker-compose git python3 sops];
      text = ''
        exec python3 ${../../server/_servarr-exact-revision.py} "$@"
      '';
    };
    statefulAdguardTransition = pkgs.writeShellApplication {
      name = "discovery-stateful-adguard-transition";
      runtimeInputs = with pkgs; [
        acl
        attr
        btrfs-progs
        coreutils
        docker
        docker-compose
        git
        jq
        python3
        rsync
        sudo
        statefulAdguardInventory
        statefulAdguardPostcheck
        statefulStackOps
        servarrExactRevision
      ];
      text = ''
        export P2_ADGUARD_TARGET_COMMIT=9969e35dca0cfb49a68bda3ba10156667cd4b53f
        export P2_ADGUARD_IMAGE_ADGUARD=adguard/adguardhome:v0.108.0-b.83@sha256:8399ec9bdcb76d5ef4f217ed2d0272dc9f3fb283eb2613744610988232d91927
        export P2_ADGUARD_IMAGE_EXPORTER=ghcr.io/henrywhitaker3/adguard-exporter:v1.2.1@sha256:42a9581bae4a91e6d4985415d1fe89ab9b1f50fbe2945a1c122d212d6354b747
        export P2_ADGUARD_INVENTORY_SOURCE=${./_stateful-adguard-inventory.py}
        export P2_ADGUARD_PREFLIGHT_SOURCE=${./_stateful-adguard-preflight.py}
        export P2_ADGUARD_FIXTURE_SOURCE=${./_stateful-adguard-transition-fixture.py}
        export P2_ADGUARD_EXECUTOR_SOURCE=${./_stateful-adguard-transition-exec.py}
        export P2_ADGUARD_REVISION_SOURCE=${./_stateful-adguard-transition-revision.py}
        export P2_ADGUARD_EXACT_REVISION_SOURCE=${../../server/_servarr-exact-revision.py}
        export P2_ADGUARD_POSTCHECK_SOURCE=${./_stateful-adguard-postcheck.py}
        export P2_ADGUARD_EXACT_REVISION_BIN=${servarrExactRevision}/bin/servarr-exact-revision
        export P2_ADGUARD_POSTCHECK_BIN=${statefulAdguardPostcheck}/bin/discovery-stateful-adguard-postcheck
        export P2_ADGUARD_REVISION_PREFETCH_PATH=/var/lib/stateful-stack-migrations/p2-adguard/revision-prefetch.json
        export P2_ADGUARD_DECLARATIVE_WIRING_SHA256=${builtins.hashFile "sha256" ../../server/_servarr-exact-revision.py}
        export P2_ADGUARD_POSTCHECK_WIRING_SHA256=${builtins.hashFile "sha256" ./_stateful-adguard-postcheck.py}
        case "''${1:-}" in
          execute) exec python3 ${./_stateful-adguard-transition-exec.py} "$@" ;;
          *) exec python3 ${./_stateful-adguard-transition.py} "$@" ;;
        esac
      '';
    };
    statefulSwagTransition = pkgs.writeShellApplication {
      name = "discovery-stateful-swag-transition";
      runtimeInputs = with pkgs; [
        btrfs-progs
        coreutils
        curl
        docker
        docker-compose
        git
        openssl
        python3
        sudo
        statefulSwagInventory
        statefulSwagPreflight
      ];
      text = ''
        exec python3 ${./_stateful-swag-transition.py} "$@"
      '';
    };
    statefulSwagTransitionAmendment = pkgs.writeShellApplication {
      name = "discovery-stateful-swag-transition-amendment";
      runtimeInputs = with pkgs; [
        btrfs-progs
        coreutils
        curl
        docker
        docker-compose
        git
        openssl
        python3
        sudo
        statefulSwagInventory
        statefulSwagPreflight
      ];
      text = ''
        export SWAG_TRANSITION_BASE=${./_stateful-swag-transition.py}
        exec python3 ${./_stateful-swag-transition-amendment.py} "$@"
      '';
    };
  in {
    environment.systemPackages = [
      statefulStackOps
      statefulAdguardInventory
      statefulAdguardPreflight
      statefulAdguardPostcheck
      statefulAdguardTransition
      statefulSwagAdopt
      statefulSwagInventory
      statefulSwagPreflight
      statefulSwagTransition
      statefulSwagTransitionAmendment
    ];
    systemd.services.discovery-stateful-stack-fixture = {
      description = "Prove discovery state migration helpers on a disposable fixture";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${statefulStackFixture}/bin/discovery-stateful-stack-fixture";
      };
    };
    systemd.tmpfiles.rules = [
      "d /var/lib/stateful-stack-migrations 0700 root root - -"
      "d /var/lib/stateful-stack-migrations/p0-fixture 0700 root root - -"
      "d /var/lib/stateful-stack-migrations/p2-adguard 0770 root users - -"
    ];
  };
}
