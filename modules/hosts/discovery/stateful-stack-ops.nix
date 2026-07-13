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
  in {
    environment.systemPackages = [statefulStackOps];
  };
}
