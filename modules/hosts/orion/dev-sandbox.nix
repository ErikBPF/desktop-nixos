# orion-dev-sandbox — isolated cloud-hypervisor MicroVM ("lander") for remote
# dev work (Claude Code / VS Code Remote-SSH), structurally unable to touch
# orion's GPU / cache / builder responsibilities.
#
# RFC: docs/proposals/2026-07-10-orion-dev-sandbox-microvm.md
#
# 🔴 RUNTIME PREREQUISITE (Blocker 0): orion's BIOS has SVM/AMD-V disabled
# (`kvm_amd: SVM not supported by CPU`), so there is no /dev/kvm and the guest
# CANNOT BOOT yet. This module still *evaluates and builds* (`just dry orion`
# exercises the full guest closure) — it just won't start until SVM is enabled
# in firmware + reboot. Do not `switch-orion` with this live before that.
#
# Isolation (see RFC §6): no GPU passthrough (guest never sees amdgpu), hard RAM
# cap, own store, and a low-CPUWeight slice so GPU-serving always preempts it.
{
  config,
  inputs,
  ...
}: let
  m = config.flake.modules;
  inherit (config) username;

  guestName = "lander";
  guestIp = "10.100.0.2";
  hostBridgeIp = "10.100.0.1";
  subnet = "10.100.0";
  externalIf = "enp4s0"; # orion's physical NIC (see `ip -br link`)

  # Laptop's user key (mirror of modules/user.nix:23) so Remote-SSH / the
  # `lander` alias work without extra provisioning.
  laptopKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMxdE+uAvR4Nm2XwZNjTf2Ae8PlrRtnZUI6BBrbGl78u erikbogado@gmail.com";
  nixBuilderKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIInTVlltDh3Q+FTusCXKsQ4Dr0pzpQHH4dAlcGXj0FPY nix-builder@laptop";

  # Host dir handed to the guest over virtiofs, holding the decrypted tailscale
  # authkey. Populated by the pre-provision oneshot below (mirrors kepler's
  # k3s token-share pattern) — keeps sops out of the guest.
  tsAuthHostDir = "/var/lib/microvms/${guestName}/ts-auth";

  # The guest: a LEAN hand-rolled NixOS (like kepler's _k3s-node, NOT the heavy
  # fleet profile-base) — just what a dev box needs, imported home dev modules,
  # networkd static IP, its own tailscale identity.
  guest = {
    pkgs,
    lib,
    ...
  }: {
    imports = [
      inputs.home-manager.nixosModules.default
      # Auto-generated from the syncthing-fleet topology (hosts.lander) — gives
      # the guest its syncthing config + the dev-workspace folder ↔ laptop.
      m.nixos."${guestName}-syncthing"
    ];

    # --- guest hardware envelope (RFC §5) ---------------------------------
    microvm = {
      hypervisor = "cloud-hypervisor";
      vcpu = 8; # D1: shares cores, yields via the host slice's CPUWeight
      mem = 24576; # 24 GiB hard cap of orion's 62 GiB
      interfaces = [
        {
          type = "tap";
          id = "vm-${guestName}"; # bridged into br-dev by the host (below)
          mac = "02:00:00:00:0d:01"; # locally-administered
        }
      ];
      shares = [
        {
          # Guest reuses orion's /nix/store read-only (small root image).
          tag = "ro-store";
          source = "/nix/store";
          mountPoint = "/nix/.ro-store";
          proto = "virtiofs";
        }
        {
          tag = "ts-auth";
          source = tsAuthHostDir;
          mountPoint = "/var/lib/tailscale-auth";
          proto = "virtiofs";
        }
      ];
      volumes = [
        {
          image = "root.img"; # under /var/lib/microvms/${guestName}, on NVMe
          mountPoint = "/";
          size = 40960; # 40 GiB writable root
        }
      ];
    };

    # --- guest networking: static on the private subnet, gw = orion --------
    networking = {
      hostName = guestName;
      useNetworkd = true;
      firewall = {
        enable = true;
        allowedTCPPorts = [2222 22000]; # sshd + syncthing
        allowedUDPPorts = [21027]; # syncthing discovery
      };
    };
    systemd.network.enable = true;
    systemd.network.networks."10-eth" = {
      matchConfig.Type = "ether";
      matchConfig.Kind = "!*"; # exclude virtual devices
      networkConfig = {
        Address = "${guestIp}/24";
        Gateway = hostBridgeIp;
        DNS = hostBridgeIp;
        DHCP = "no";
      };
    };

    # --- access: sshd on 2222, passwordless wheel, fish -------------------
    services.openssh = {
      enable = true;
      ports = [2222];
      settings = {
        PasswordAuthentication = false;
        PermitRootLogin = "prohibit-password";
      };
    };
    programs.fish.enable = true;
    security.sudo.wheelNeedsPassword = false;
    users.users.${username} = {
      isNormalUser = true;
      extraGroups = ["wheel"];
      shell = pkgs.fish;
      openssh.authorizedKeys.keys = [laptopKey nixBuilderKey];
    };
    users.users.root.openssh.authorizedKeys.keys = [laptopKey];

    # --- the guest's own tailnet identity (RFC §7) ------------------------
    # Reachable as `lander` by MagicDNS from the laptop, roaming. Authkey comes
    # in over virtiofs from the host (no sops in the guest). NOTE runtime: the
    # shared authkey must be reusable/ephemeral or the guest won't register.
    services.tailscale = {
      enable = true;
      authKeyFile = "/var/lib/tailscale-auth/authkey";
      extraSetFlags = [
        "--accept-dns=true"
        "--accept-routes"
      ];
      extraUpFlags = ["--hostname=${guestName}"];
    };

    # --- dev environment (RFC §8) — home dev modules ----------------------
    home-manager = {
      useGlobalPkgs = true;
      backupFileExtension = "backup";
      users.${username} = {
        imports = [
          m.home.fish
          m.home.git
          m.home.starship
          m.home.direnv
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

    # --- guest nix + base knobs -------------------------------------------
    nix.settings = {
      experimental-features = ["nix-command" "flakes"];
      trusted-users = ["root" username];
      substituters = ["http://${hostBridgeIp}:5000?priority=5" "https://cache.nixos.org"];
      trusted-public-keys = [
        "orion:4hKV3v/D0wY4JIk1TIcgaBIjM9VliJnwZyRUjCZhtSg="
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      ];
    };
    # nixpkgs is the host's instance (microvm passes orion's pkgs, which already
    # has allowUnfree) — the guest must not re-configure nixpkgs.
    time.timeZone = "America/Sao_Paulo";
    system.stateVersion = "25.11";
  };
in {
  flake.modules.nixos.orion-dev-sandbox = {
    config,
    lib,
    pkgs,
    ...
  }: {
    imports = [inputs.microvm.nixosModules.host];

    microvm.vms.${guestName} = {config = guest;};
    microvm.autostart = [guestName];

    # --- host-side bridge + NAT for the guest tap (RFC §7) ----------------
    # orion runs NetworkManager; the dev bridge/tap are networkd-managed and
    # marked NM-unmanaged so the two don't fight over them.
    networking.networkmanager.unmanaged = ["interface-name:br-dev" "interface-name:vm-${guestName}"];
    systemd.network = {
      netdevs."20-br-dev".netdevConfig = {
        Name = "br-dev";
        Kind = "bridge";
      };
      networks."20-br-dev" = {
        matchConfig.Name = "br-dev";
        address = ["${hostBridgeIp}/24"];
        linkConfig.RequiredForOnline = "no";
      };
      networks."21-dev-tap" = {
        matchConfig.Name = "vm-${guestName}";
        networkConfig.Bridge = "br-dev";
        linkConfig.RequiredForOnline = "no";
      };
    };
    networking.firewall.trustedInterfaces = ["br-dev"];
    networking.nat = {
      enable = true;
      internalInterfaces = ["br-dev"];
      externalInterface = externalIf;
      # Also let the guest reach the tailnet via orion's tailscale0.
      extraCommands = ''
        iptables -t nat -A POSTROUTING -s ${subnet}.0/24 -o tailscale0 -j MASQUERADE
      '';
      extraStopCommands = ''
        iptables -t nat -D POSTROUTING -s ${subnet}.0/24 -o tailscale0 -j MASQUERADE 2>/dev/null || true
      '';
    };

    # --- isolation: yield-to-GPU slice (RFC §6, D1 = yield-only) ----------
    systemd.slices."dev-sandbox" = {
      description = "orion dev-sandbox MicroVM — yields to GPU serving";
      sliceConfig = {
        CPUWeight = 20; # << default 100: GPU-serving/training always wins
        MemoryHigh = "26G"; # soft ceiling above the 24 GiB guest alloc
      };
    };

    # --- pre-provision: guest state dir + tailscale authkey (before boot) --
    # tmpfiles can't create dirs under a root-owned parent chain reliably for
    # the virtiofs source, and we must decrypt the sops authkey at runtime, so
    # use a oneshot ordered before the guest (mirrors kepler k3s-cluster.nix).
    systemd.services."dev-sandbox-preprovision" = {
      description = "Provision lander MicroVM state + tailscale authkey";
      wantedBy = ["microvm@${guestName}.service"];
      before = ["microvm@${guestName}.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        install -d -m 0700 ${tsAuthHostDir}
        install -m 0600 ${config.sops.secrets."tailscale_authkey".path} ${tsAuthHostDir}/authkey
      '';
    };

    # Route the guest unit into the yield slice via a drop-in (don't clobber
    # microvm.nix's template unit).
    systemd.services."microvm@${guestName}" = {
      overrideStrategy = "asDropin";
      serviceConfig.Slice = "dev-sandbox.slice";
    };
  };
}
