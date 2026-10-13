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
    # Apollo AI runtime (vLLM + LMCache). Verified recipe 2026-10-12; the manual
    # reference lives in homelab-gitops/apps/homelab/apollo-qwen27b.
    # One container: LMCache and vLLM must share the CUDA/IPC namespace or KV
    # registration never completes. util 0.80 leaves LMCache GPU headroom
    # (0.90 OOMs its registration). The image is a local patched build, pinned by id.
    apolloAiModel = "/mnt/data/ai/models/gittensor/Qwen3.8-27B-NVFP4-RTX5090-0cc2795";
    apolloAiImage = "sha256:dce379422d6420af4006eacb78c677d2e864446858ab6b31b28aad2e86c6a7bf";
    apolloAiPodman = pkgs.writeShellScript "apollo-ai-podman" ''
      set -euo pipefail
      bin=${pkgs.podman}/bin/podman
      vendored=/mnt/data/ai-evaluation/runtimes/tools/podman/bin/podman
      [[ -x $vendored ]] && bin=$vendored
      exec "$bin" --root /mnt/data/ai/cache/podman-root --runroot /run/apollo-ftw-containers "$@"
    '';
    apolloAiRuntime = let
      serveLmcache = pkgs.writeShellScript "serve-lmcache.sh" ''
        set -euo pipefail
        export LMCACHE_TRACK_USAGE=false PYTHONHASHSEED=0
        exec lmcache server --host 127.0.0.1 --port 11550 \
          --http-host 127.0.0.1 --http-port 11552 --prometheus-port 11551 \
          --chunk-size 864 --separate-object-groups \
          --l1-size-gb 8 --l1-init-size-gb 8 --eviction-policy LRU \
          --max-gpu-workers 2 --max-cpu-workers 2
      '';
      serveVllm = pkgs.writeShellScript "serve-vllm.sh" ''
        set -euo pipefail
        export VLLM_SERVER_DEV_MODE=1 VLLM_CACHE_ROOT=/cache/vllm HF_HOME=/cache/hf \
               XDG_CACHE_HOME=/cache/xdg TORCH_HOME=/cache/torch CUDA_CACHE_PATH=/cache/cuda \
               HF_HUB_OFFLINE=1 NCCL_P2P_DISABLE=1 VLLM_ALLOW_LONG_MAX_MODEL_LEN=1 LMCACHE_TRACK_USAGE=false
        exec vllm serve /model --served-model-name qwen38-27b-nvfp4 --host 0.0.0.0 --port 11542 \
          --tensor-parallel-size 2 --no-enable-flashinfer-autotune --disable_custom_all_reduce --trust-remote-code \
          --kv-cache-dtype fp8 --max-model-len 105000 --max-num-seqs 4 \
          --compilation-config '{"cudagraph_mode":"PIECEWISE"}' \
          --mamba-cache-dtype bfloat16 --mamba-ssm-cache-dtype bfloat16 --mamba-cache-mode align \
          --gpu-memory-utilization 0.80 --max-num-batched-tokens 1727 \
          --enable-prefix-caching --enable-chunked-prefill \
          --limit-mm-per-prompt '{"video":0}' --mm-processor-kwargs '{"max_pixels":1000000}' \
          --reasoning-parser qwen3 --tool-call-parser qwen3_xml --enable-auto-tool-choice \
          --default-chat-template-kwargs '{"preserve_thinking":true}' \
          --speculative-config '{"method":"mtp","num_speculative_tokens":6}' \
          --kv-transfer-config '{"kv_connector":"LMCacheMPConnector","kv_connector_module_path":"lmcache.integration.vllm.lmcache_mp_connector","kv_role":"kv_both","kv_connector_extra_config":{"lmcache.mp.host":"127.0.0.1","lmcache.mp.port":11550,"lmcache.mp.autostart":false}}'
      '';
      supervise = pkgs.writeShellScript "supervise.sh" ''
        set -euo pipefail
        children=()
        cleanup() { trap - EXIT TERM INT; kill -TERM "''${children[@]}" 2>/dev/null || true; wait || true; }
        trap cleanup EXIT TERM INT
        bash /trial/serve-lmcache.sh & children+=("$!")
        sleep 8
        bash /trial/serve-vllm.sh & children+=("$!")
        wait -n "''${children[@]}"
        exit 1
      '';
    in
      pkgs.runCommand "apollo-ai-runtime" {} ''
        mkdir -p $out
        cp ${serveLmcache} $out/serve-lmcache.sh
        cp ${serveVllm} $out/serve-vllm.sh
        cp ${supervise} $out/supervise.sh
      '';
    apolloAiPreflight = pkgs.writeShellScript "apollo-ai-preflight" ''
      set -euo pipefail
      export PATH=/run/current-system/sw/bin:/run/wrappers/bin:/usr/bin:/bin
      input_rules=$(iptables -S INPUT)
      chain_rules=$(iptables -S apollo-qwen-litellm)
      grep -qxF -- '-A INPUT -d 100.77.14.27/32 -p tcp -m tcp --dport 11542 -j apollo-qwen-litellm' <<<"$input_rules"
      grep -qxF -- '-A INPUT -d 100.77.14.27/32 -p tcp -m tcp --dport 11560 -j apollo-qwen-litellm' <<<"$input_rules"
      [[ $chain_rules == '-N apollo-qwen-litellm
      -A apollo-qwen-litellm -i lo -j ACCEPT
      -A apollo-qwen-litellm -s 100.103.52.100/32 -i tailscale0 -p tcp -m multiport --dports 11542,11560 -j ACCEPT
      -A apollo-qwen-litellm -j REJECT --reject-with icmp-port-unreachable' ]]
      [[ $(findmnt -n -o SOURCE /mnt/data) == /dev/sdc1 ]]
      gpu_uuids=$(nvidia-smi --query-gpu=uuid --format=csv,noheader)
      [[ $gpu_uuids == *GPU-af808452-3544-e84a-b33a-fc5588ede436* ]]
      [[ $gpu_uuids == *GPU-818843e6-ce30-5d98-a4b4-8d8580aaa049* ]]
      ${apolloAiPodman}/bin/apollo-ai-podman image exists ${apolloAiImage}
      [[ -r ${apolloAiModel}/config.json ]]
    '';
    # Adopt any pre-existing container of the same name (e.g. the ad-hoc one
    # started by the manual launch.sh) so the first start and restarts are clean.
    apolloAiClean = pkgs.writeShellScript "apollo-ai-clean" ''
      set -u
      ${apolloAiPodman}/bin/apollo-ai-podman rm -f apollo-qwen38 >/dev/null 2>&1 || true
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
    # Reboot-durable host service for the verified vLLM + LMCache recipe. Podman
    # runs the single container in the foreground so systemd tracks it; `run --rm`
    # plus ExecStop stop and remove it. The preflight refuses to start unless the
    # firewall, filesystem, both GPUs, the pinned image and the model path match.
    systemd.services.apollo-ai = {
      description = "Apollo Qwen3.8-27B NVFP4 vLLM + LMCache runtime";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target" "apollo-ai-storage.service"];
      wants = ["network-online.target"];
      requires = ["apollo-ai-storage.service"];
      unitConfig.RequiresMountsFor = "/mnt/data";
      serviceConfig = {
        Type = "simple";
        ExecStartPre = [
          "${apolloAiPreflight}"
          "${apolloAiClean}"
        ];
        ExecStart = [
          "${apolloAiPodman}/bin/apollo-ai-podman"
          "run"
          "--rm"
          "--name"
          "apollo-qwen38"
          "--pull=never"
          "--network=host"
          "--shm-size=8g"
          "--user"
          "1000:100"
          "--cpus=8"
          "--memory=80g"
          "--memory-swap=80g"
          "--security-opt=no-new-privileges"
          "--device"
          "nvidia.com/gpu=all"
          "--volume"
          "${apolloAiModel}:/model:ro"
          "--volume"
          "/mnt/data/ai/cache:/cache"
          "--volume"
          "${apolloAiRuntime}:/trial:ro"
          "--entrypoint"
          "/bin/bash"
          "${apolloAiImage}"
          "/trial/supervise.sh"
        ];
        ExecStop = ["${apolloAiPodman}/bin/apollo-ai-podman" "stop" "-t" "60" "apollo-qwen38"];
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
