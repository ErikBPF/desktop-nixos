# orion-gemini — isolated NixOS container ("gemini") for remote dev work
# (Claude Code / VS Code Remote-SSH), sharing orion's CPU/RAM (and GPU later)
# rather than walling them off.
#
# RFC: docs/proposals/2026-07-10-orion-dev-sandbox-microvm.md
#
# Was a microVM (guest "lander") for HARD isolation, but the goal shifted to
# "isolated env, shared resources" — a VM can't share the GPU, a container can.
# So this is a declarative systemd-nspawn container: shares the host kernel →
# CPU/RAM/GPU are natively shared (none are netns-scoped). Trade-off: this is
# ENVIRONMENT isolation (own userspace/fs/procs), NOT the microVM's structural
# resource protection — a shared box can contend with orion's workloads.
#
# GPU: intentionally NOT wired yet (user deferred it). To add later, uncomment
# the allowedDevices/bindMounts for /dev/kfd + /dev/dri and the render/video
# groups — see the block marked "GPU (deferred)".
#
# Networking: privateNetwork so it doesn't collide with orion's own sshd:2222 /
# syncthing:22000 on the shared netns. Reuses the br-dev bridge + NAT + the
# tailscale-authkey provisioning oneshot (all host-side, below). tailscale runs
# INSIDE the container (enableTun) → gemini is its own tailnet node, reachable
# as `gemini` by MagicDNS exactly like a normal fleet host.
{
  config,
  inputs,
  ...
}: let
  m = config.flake.modules;
  inherit (config) username;

  ctName = "gemini";
  ctIp = "10.100.0.2";
  hostBridgeIp = "10.100.0.1";
  subnet = "10.100.0";
  externalIf = "enp4s0"; # orion's physical NIC

  laptopKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMxdE+uAvR4Nm2XwZNjTf2Ae8PlrRtnZUI6BBrbGl78u erikbogado@gmail.com";
  nixBuilderKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIInTVlltDh3Q+FTusCXKsQ4Dr0pzpQHH4dAlcGXj0FPY nix-builder@laptop";

  # Host dir bind-mounted into the container, holding the decrypted tailscale
  # authkey (populated by the pre-provision oneshot below).
  tsAuthHostDir = "/var/lib/${ctName}/ts-auth";
in {
  flake.modules.nixos.orion-gemini = {
    config,
    pkgs,
    lib,
    ...
  }: {
    containers.${ctName} = {
      autoStart = true;
      # Own netns so the container's sshd/syncthing don't collide with orion's
      # (both would want :2222 / :22000). CPU/RAM/GPU are unaffected by this —
      # they are shared regardless.
      privateNetwork = true;
      hostBridge = "br-dev"; # host-side bridge defined below
      localAddress = "${ctIp}/24";

      enableTun = true; # grant /dev/net/tun + CAP_NET_ADMIN for in-container tailscale

      bindMounts = {
        # tailscale authkey (decrypted host-side, see the oneshot).
        "/var/lib/tailscale-auth" = {
          hostPath = tsAuthHostDir;
          isReadOnly = false;
        };
      };
      # NOTE: we deliberately do NOT forward orion's nix-daemon socket. Bind-
      # mounting it into the nspawn container is unreliable — it goes stale and
      # returns "Connection reset by peer" whenever the host daemon restarts,
      # which crashed the container's home-manager activation (→ bare shell).
      # The container runs its OWN nix-daemon against the RO shared store; HM
      # only needs to symlink already-built paths, so no writable store/daemon
      # forward is required. Consequence: in-container `nix build`/`nix develop`
      # of NEW derivations can't write the RO store — build on the orion host.

      # GPU (deferred) — uncomment to give the container ROCm/DRM access:
      # allowedDevices = [
      #   { node = "/dev/kfd"; modifier = "rwm"; }
      #   { node = "char-drm"; modifier = "rwm"; }
      # ];
      # bindMounts."/dev/kfd" = { hostPath = "/dev/kfd"; isReadOnly = false; };
      # bindMounts."/dev/dri" = { hostPath = "/dev/dri"; isReadOnly = false; };
      # (and add "render" "video" to the container user's extraGroups)

      config = {lib, ...}: {
        imports = [
          inputs.home-manager.nixosModules.default
          # Declarative prebuilt nix-index db + comma, so the zsh
          # command-not-found handler (nix-locate/comma) has a database.
          m.nixos.nix-index
          # The shared CLI toolbox (eza/ripgrep/fd/fzf/… — a NixOS module via
          # environment.systemPackages) that the zsh aliases assume.
          m.nixos.packages-shared
          # Auto-generated from the syncthing-fleet topology (hosts.gemini).
          m.nixos."${ctName}-syncthing"
        ];

        # Reuse orion's already-configured pkgs (allowUnfree, overlays,
        # substituters) — faster eval + no nixpkgs re-config here.
        nixpkgs.pkgs = pkgs;

        networking = {
          hostName = ctName;
          useHostResolvConf = false;
          defaultGateway = hostBridgeIp;
          nameservers = ["1.1.1.1" "9.9.9.9"];
          firewall = {
            enable = true;
            allowedTCPPorts = [2222 22000];
            allowedUDPPorts = [21027];
          };
        };

        # Access: sshd on 2222, passwordless wheel, zsh.
        services.openssh = {
          enable = true;
          ports = [2222];
          settings = {
            PasswordAuthentication = false;
            PermitRootLogin = "prohibit-password";
          };
        };
        programs.zsh.enable = true;
        security.sudo.wheelNeedsPassword = false;
        users.users.${username} = {
          isNormalUser = true;
          uid = 1000; # match orion's erik so the forwarded nix-daemon trusts it
          extraGroups = ["wheel"];
          shell = pkgs.zsh;
          openssh.authorizedKeys.keys = [laptopKey nixBuilderKey];
        };
        users.users.root.openssh.authorizedKeys.keys = [laptopKey];

        # Own tailnet identity (MagicDNS `gemini`). Authkey is an OAuth client
        # secret (tskey-client-*) → tailscale requires a tag; reuse tag:server.
        services.tailscale = {
          enable = true;
          authKeyFile = "/var/lib/tailscale-auth/authkey";
          extraSetFlags = [
            "--accept-dns=true"
            "--accept-routes"
          ];
          extraUpFlags = [
            "--hostname=${ctName}"
            "--advertise-tags=tag:server"
          ];
        };

        # In-container nix via the forwarded host daemon.
        nix.settings.experimental-features = ["nix-command" "flakes"];

        # Dev environment — the same home modules the laptop uses.
        home-manager = {
          useGlobalPkgs = true;
          useUserPackages = true;
          backupFileExtension = "backup";
          users.${username} = {
            imports = [
              # profile-base pulls m.home.sops → needs the sops-nix HM module
              # (home-manager-base provides it on real hosts; wire it here).
              inputs.sops-nix.homeManagerModules.sops
              # Shared home baseline (bash, git, bat, direnv, nix-tools,
              # packages-shared=eza/ripgrep/…) + the interactive shell QoL
              # (zsh/starship/atuin/zoxide/yazi/btop — split out of profile-base
              # by the profiles refactor, so BOTH are needed) + the dev agents.
              m.home.profile-base
              m.home.profile-interactive
              m.home.claude-code
              m.home.codex
              m.home.opencode
              m.home.vscode
              m.home.herdr
              m.home.tmux
            ];
            home = {
              inherit username;
              homeDirectory = "/home/${username}";
              stateVersion = "25.11";
            };
            programs.home-manager.enable = true;
          };
        };

        system.stateVersion = "25.11";
      };
    };

    # --- host-side bridge + NAT for the container's veth (br-dev) ----------
    # orion runs NetworkManager; br-dev is networkd-managed + NM-unmanaged.
    networking.networkmanager.unmanaged = ["interface-name:br-dev" "interface-name:ve-${ctName}"];
    systemd.network = {
      enable = true;
      netdevs."20-br-dev".netdevConfig = {
        Name = "br-dev";
        Kind = "bridge";
      };
      networks."20-br-dev" = {
        matchConfig.Name = "br-dev";
        address = ["${hostBridgeIp}/24"];
        linkConfig.RequiredForOnline = "no";
      };
      networks."21-dev-veth" = {
        matchConfig.Name = "ve-${ctName}";
        networkConfig.Bridge = "br-dev";
        linkConfig.RequiredForOnline = "no";
      };
    };
    networking.firewall.trustedInterfaces = ["br-dev"];
    networking.nat = {
      enable = true;
      internalInterfaces = ["br-dev"];
      externalInterface = externalIf;
      extraCommands = ''
        iptables -t nat -A POSTROUTING -s ${subnet}.0/24 -o tailscale0 -j MASQUERADE
      '';
      extraStopCommands = ''
        iptables -t nat -D POSTROUTING -s ${subnet}.0/24 -o tailscale0 -j MASQUERADE 2>/dev/null || true
      '';
    };

    # --- pre-provision the tailscale authkey before the container starts ---
    systemd.services."${ctName}-preprovision" = {
      description = "Provision ${ctName} tailscale authkey";
      wantedBy = ["container@${ctName}.service"];
      before = ["container@${ctName}.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        install -d -m 0700 ${tsAuthHostDir}
        install -m 0600 ${config.sops.secrets."tailscale_authkey".path} ${tsAuthHostDir}/authkey
      '';
    };
  };
}
