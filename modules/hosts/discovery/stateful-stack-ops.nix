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
        statefulSwagInventory
        statefulSwagPreflight
      ];
      text = ''
        exec python3 ${./_stateful-swag-transition.py} "$@"
      '';
    };
  in {
    environment.systemPackages = [
      statefulStackOps
      statefulSwagAdopt
      statefulSwagInventory
      statefulSwagPreflight
      statefulSwagTransition
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
    ];
  };
}
