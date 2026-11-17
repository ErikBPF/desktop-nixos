{
  config,
  inputs,
  ...
}: let
  m = config.flake.modules;
in {
  configurations.nixos.apollo.module = {
    lib,
    modulesPath,
    pkgs,
    ...
  }: let
    safeAgentAliases = {
      claude = "command claude";
      c = "codex";
      cc = "code . ; codex";
      oc = "opencode";
      occ = "code . ; opencode";
    };
    # Apollo AI runtime (dsx, DeepSeek-V4.1-Flash-1017 T16). Replaces the vLLM +
    # LMCache + pqnld stack measured 2026-11-16/17: 17 tok/s decode and 740 tok/s
    # prefill at a 28K prompt, 213K-token fills served, needle retrieved at 213K,
    # and a parked session restored in 0.17 s. The image is a local build pinned by
    # id; rebuild it when dsx moves and re-pin here.
    apolloAiModelDir = "/mnt/data/ai/models/dsx";
    apolloAiPack = "DeepSeek-V4.1-Flash-1017-dsx-t16.gguf";
    apolloAiRankFile = "expert-rank.json";
    apolloAiImage = "sha256:c57e24782ab02bad202dd033c08d9318d643f0ec631840b181bcc040bf985e42";
    apolloAiPodman = pkgs.writeShellScript "apollo-ai-podman" ''
      set -euo pipefail
      bin=${pkgs.podman}/bin/podman
      vendored=/mnt/data/ai-evaluation/runtimes/tools/podman/bin/podman
      [[ -x $vendored ]] && bin=$vendored
      exec "$bin" --root /mnt/data/ai/cache/podman-root --runroot /run/apollo-ftw-containers "$@"
    '';
    apolloAiPreflight = pkgs.writeShellScript "apollo-ai-preflight" ''
      set -euo pipefail
      export PATH=/run/current-system/sw/bin:/run/wrappers/bin:/usr/bin:/bin
      input_rules=$(iptables -S INPUT)
      chain_rules=$(iptables -S apollo-qwen-litellm)
      grep -qxF -- '-A INPUT -d ${config.flake.fleet.hosts.apollo.tailscaleIp}/32 -p tcp -m tcp --dport 11542 -j apollo-qwen-litellm' <<<"$input_rules"
      grep -qxF -- '-A INPUT -d ${config.flake.fleet.hosts.apollo.tailscaleIp}/32 -p tcp -m tcp --dport 11560 -j apollo-qwen-litellm' <<<"$input_rules"
      [[ $chain_rules == '-N apollo-qwen-litellm
      -A apollo-qwen-litellm -i lo -j ACCEPT
      -A apollo-qwen-litellm -s ${config.flake.fleet.hosts.discovery.tailscaleIp}/32 -i tailscale0 -p tcp -m multiport --dports 11542,11560 -j ACCEPT
      -A apollo-qwen-litellm -j REJECT --reject-with icmp-port-unreachable' ]]
      # ext4 UUID of the 4 TB model volume (serial S6PJNS0YA01548X).
      # Device names reorder across boots; check the filesystem UUID instead.
      [[ $(findmnt -n -o UUID /mnt/data) == f87b86ad-82ab-4187-bc84-66ea618e0c3a ]]
      gpu_uuids=$(nvidia-smi --query-gpu=uuid --format=csv,noheader)
      [[ $gpu_uuids == *GPU-af808452-3544-e84a-b33a-fc5588ede436* ]]
      [[ $gpu_uuids == *GPU-818843e6-ce30-5d98-a4b4-8d8580aaa049* ]]
      ${apolloAiPodman} image exists ${apolloAiImage}
      [[ -r ${apolloAiModelDir}/${apolloAiPack} ]]
      [[ -r ${apolloAiModelDir}/${apolloAiRankFile} ]]
    '';
    # Adopt any pre-existing container of the same name (e.g. one started by a
    # manual trial) so the first start and restarts are clean.
    apolloAiClean = pkgs.writeShellScript "apollo-ai-clean" ''
      set -u
      ${apolloAiPodman} rm -f apollo-dsx >/dev/null 2>&1 || true
    '';
  in {
    imports = [
      (modulesPath + "/installer/scan/not-detected.nix")
      inputs.disko.nixosModules.disko
      inputs.sops-nix.nixosModules.sops
      m.nixos.profile-base
      m.nixos.profile-server
      # Rootless Podman + dockerCompat, so minikube can use its podman driver
      # for the local aster stack (mirrors orion).
      m.nixos.containers
      m.nixos.nix-index
      m.nixos.hermes-client
      m.nixos.opencode-client
      m.nixos.apollo-syncthing
      m.nixos.kepler-nfs
      m.nixos.systemd-boot-counting
      m.nixos.apollo-hardware
      m.nixos.apollo-networking
      m.nixos.first-boot
      m.nixos.runtime-secret-health
      m.nixos.pangolin-newt
      m.nixos.alloy
      m.nixos.power-desktop
      m.nixos.btrfs-snapshots
    ];

    services.btrfs.autoScrub.enable = true;
    environment.systemPackages = [pkgs.stern pkgs.nvd];
    # Operator-owned trial storage; never create it on root if the mirror is absent.
    # Future inference units must require the same mount before accessing it.
    systemd.services.apollo-ai-storage = {
      description = "Prepare private AI model and cache directories on the mirror";
      wantedBy = ["multi-user.target"];
      unitConfig = {
        RequiresMountsFor = "/mnt/data";
        AssertPathIsMountPoint = "/mnt/data";
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.coreutils}/bin/install -d -m 0700 -o ${config.username} -g users /mnt/data/ai /mnt/data/ai/models /mnt/data/ai/cache";
      };
    };
    # Reboot-durable host service for the dsx DeepSeek runtime. Podman runs the
    # single container in the foreground so systemd tracks it; `run --rm` plus
    # ExecStop stop and remove it. The preflight refuses to start unless the
    # firewall, filesystem, both GPUs, the pinned image and the model files match.
    # Port 11542 is unchanged so the existing LiteLLM route and firewall rule keep
    # working; port 11560 is now unserved because pqnld was vLLM-specific.
    systemd.services.apollo-ai = {
      description = "Apollo DeepSeek-V4.1-Flash dsx runtime";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target" "apollo-ai-storage.service" "tailscaled.service"];
      wants = ["network-online.target" "tailscaled.service"];
      requires = ["apollo-ai-storage.service"];
      unitConfig.RequiresMountsFor = "/mnt/data";
      serviceConfig = {
        Type = "simple";
        # A clean systemctl stop makes podman exit 143; do not report it as failed.
        SuccessExitStatus = [143 "SIGTERM"];
        ExecStartPre = [
          "${apolloAiPreflight}"
          "${apolloAiClean}"
        ];
        ExecStart = [
          [
            "${apolloAiPodman}"
            "run"
            "--rm"
            "--name"
            "apollo-dsx"
            "--pull=never"
            "--network=host"
            "--ipc=host"
            "--ulimit"
            "memlock=-1:-1"
            "--security-opt=no-new-privileges"
            "--device"
            "nvidia.com/gpu=all"
            "--env"
            "DSX_GPUS=0,1"
            "--volume"
            "${apolloAiModelDir}:/model:ro"
            "${apolloAiImage}"
            "--model"
            "/model/${apolloAiPack}"
            "--rank"
            "/model/${apolloAiRankFile}"
            "--ctx"
            "262144"
            "--arena-gb"
            "150"
            "--cache-sessions"
            "3"
            "--session-cache-gb"
            "16"
            "--prefix-anchor-tokens"
            "16384"
            "--no-vision"
            "--host"
            "0.0.0.0"
            "--port"
            "11542"
          ]
        ];
        ExecStop = [["${apolloAiPodman}" "stop" "-t" "60" "apollo-dsx"]];
        Restart = "always";
        RestartSec = 10;
        TimeoutStartSec = "infinity";
        TimeoutStopSec = "120";
        KillMode = "mixed";
      };
    };
    security.sudo.wheelNeedsPassword = lib.mkForce false;
    services.openssh.settings = {
      AllowTcpForwarding = lib.mkForce "local";
      GatewayPorts = "no";
    };

    # Operator baseline: bound build concurrency so interactive work stays
    # responsive on this 28-thread host.
    nix.settings = {
      max-jobs = lib.mkForce 6;
      cores = lib.mkForce 2;
    };

    users.users.${config.username} = {
      linger = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIInTVlltDh3Q+FTusCXKsQ4Dr0pzpQHH4dAlcGXj0FPY nix-builder@laptop"
      ];
    };

    home-manager.users.${config.username} = {
      imports = [
        m.home.atuin
        m.home.claude-code
        m.home.codex
        m.home.tuicr
        m.home.opencode
        m.home.vscode
        m.home.nvim
        m.home.hermes-agent
        m.home.herdr
        m.home.herdr-worklab
        m.home.grafatui
        m.home.tmux
      ];
      programs.bash.shellAliases = lib.mapAttrs (_: lib.mkForce) safeAgentAliases;
      programs.zsh.shellAliases = lib.mapAttrs (_: lib.mkForce) safeAgentAliases;
    };

    boot.loader = {
      efi.canTouchEfiVariables = true;
      systemd-boot.configurationLimit = 6;
    };

    system.autoUpgrade.enable = false;
    system.stateVersion = "25.11";
    nixpkgs.hostPlatform = "x86_64-linux";
  };
}
