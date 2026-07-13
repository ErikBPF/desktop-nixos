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
  in {
    environment.systemPackages = [statefulStackOps];
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
