# drtest — throwaway deploy-rs test VM (NOT a fleet host).
#
# Purpose: prove deploy-rs end-to-end (normal switch + magic rollback) using a
# QEMU VM running on orion. Not provisioned with sops/tailscale/home-manager —
# just a minimal NixOS guest with SSH on port 2222, user erik + passwordless
# sudo, so deploy-rs can talk to it without the fleet's secret machinery.
#
# VM mechanism: nixosConfigurations.drtest.config.system.build.vm
#   - Built for x86_64-linux (orion).
#   - Uses QEMU usermode networking with hostfwd: orion:2224 → VM:2222.
#     No tap/bridge setup needed — self-contained, no host network state.
#   - deploy-rs node targets 192.168.10.220 (orion LAN IP) at port 2224.
#   - magicRollback = true: the post-activation reachability re-check hits the
#     same orion:2224 → VM:2222 path, so a broken sshd or dropped port will
#     trigger auto-revert.
#
# Justfile recipes: drtest-vm-build, drtest-vm-start, drtest-vm-stop, drtest-vm-ssh
# deploy-rs node: just deploy-rs drtest
{config, ...}: let
  m = config.flake.modules;
in {
  configurations.nixos.drtest.module = {
    lib,
    pkgs,
    modulesPath,
    ...
  }: {
    imports = [
      (modulesPath + "/installer/scan/not-detected.nix")
      # Reuse fleet openssh (port 2222, hardened, openFirewall) and sudo
      # (wheel, no password). Skip sops/tailscale/home-manager — throwaway.
      m.nixos.openssh
      m.nixos.sudo
      m.nixos.firewall
    ];

    # Minimal user: fleet SSH key, wheel group for passwordless sudo.
    users.users.erik = {
      isNormalUser = true;
      extraGroups = ["wheel"];
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMxdE+uAvR4Nm2XwZNjTf2Ae8PlrRtnZUI6BBrbGl78u erikbogado@gmail.com"
      ];
    };

    networking.hostName = "drtest";
    networking.firewall.allowedTCPPorts = [2222];

    # Allow deploy-rs to push unsigned paths. Without this the nix daemon on the
    # VM rejects `nix copy` with "lacks a signature by a trusted key".
    nix.settings.trusted-users = ["erik" "root"];

    system.stateVersion = "25.11";
    nixpkgs.hostPlatform = "x86_64-linux";

    # Bootloader: GRUB with device=nodev. The VM runner uses QEMU direct-kernel
    # boot so grub is never used at runtime. device=nodev skips MBR installation
    # (grub-install is not run for "nodev" in install-grub.pl) while the config
    # generation and switch-to-configuration still succeed. This is the only
    # bootloader configuration that works for deploy-rs on a QEMU direct-kernel VM.
    boot.loader.grub.enable = true;
    boot.loader.grub.device = "nodev";
    fileSystems."/" = {
      device = "/dev/vda";
      fsType = "ext4";
    };

    # Explicit systemd units for the QEMU VM's 9p virtfs mounts. These must be in
    # the base config (not just vmVariant) so deploy-rs activation does NOT see them
    # as "gone" units and try to stop/reload the live mounts.
    #
    # Why units instead of fileSystems: fstab-generated .mount units have
    # SourcePath=/etc/fstab, and when /etc/fstab symlink changes (even to identical
    # content) systemd marks them as changed → activation tries to reload overlay
    # mount → "Failed to reload nix-store.mount" → deploy-rs rollback. Explicit
    # unit files in the Nix store don't have this SourcePath issue.
    #
    # These units are no-ops on a real (non-VM) machine since the 9p devices don't
    # exist; x-initrd.mount prevents auto-activation at runtime.
    systemd.units."nix-.ro-store.mount".text = ''
      [Unit]
      Documentation=man:fstab(5) man:systemd-fstab-generator(8)
      RequiresMountsFor=/sysroot/nix/.ro-store

      [Mount]
      What=nix-store
      Where=/nix/.ro-store
      Type=9p
      Options=x-initrd.mount,trans=virtio,version=9p2000.L,msize=16384,x-systemd.requires=modprobe@9pnet_virtio.service,cache=loose
    '';
    systemd.units."nix-.rw-store.mount".text = ''
      [Unit]
      Documentation=man:fstab(5) man:systemd-fstab-generator(8)

      [Mount]
      What=tmpfs
      Where=/nix/.rw-store
      Type=tmpfs
      Options=x-initrd.mount,mode=0755
    '';
    systemd.units."nix-store.mount".text = ''
      [Unit]
      Documentation=man:fstab(5) man:systemd-fstab-generator(8)
      RequiresMountsFor=/sysroot/nix/.ro-store /sysroot/nix/.rw-store/upper /sysroot/nix/.rw-store/work
      Before=local-fs.target

      [Mount]
      What=overlay
      Where=/nix/store
      Type=overlay
      Options=x-initrd.mount,lowerdir=/sysroot/nix/.ro-store,upperdir=/sysroot/nix/.rw-store/upper,workdir=/sysroot/nix/.rw-store/work,x-initrd.mount,x-systemd.requires-mounts-for=/sysroot/nix/.ro-store,x-systemd.requires-mounts-for=/sysroot/nix/.rw-store/upper,x-systemd.requires-mounts-for=/sysroot/nix/.rw-store/work
    '';
    systemd.units."tmp-shared.mount".text = ''
      [Unit]
      Documentation=man:fstab(5) man:systemd-fstab-generator(8)

      [Mount]
      What=shared
      Where=/tmp/shared
      Type=9p
      Options=x-initrd.mount,trans=virtio,version=9p2000.L,msize=16384,x-systemd.requires=modprobe@9pnet_virtio.service
    '';
    systemd.units."tmp-xchg.mount".text = ''
      [Unit]
      Documentation=man:fstab(5) man:systemd-fstab-generator(8)

      [Mount]
      What=xchg
      Where=/tmp/xchg
      Type=9p
      Options=x-initrd.mount,trans=virtio,version=9p2000.L,msize=16384,x-systemd.requires=modprobe@9pnet_virtio.service
    '';

    # VM-specific overrides: usermode networking with hostfwd so no tap
    # infrastructure is needed on orion.
    virtualisation.vmVariant = {
      boot.kernelParams = ["net.ifnames=0"];

      virtualisation = {
        cores = 2;
        diskSize = 4096;
        memorySize = 1024;
        graphics = false;
        # Usermode networking: host port 2224 → guest port 2222 (sshd).
        # No tap, no iptables rules, no NAT — fully self-contained.
        qemu.networkingOptions = lib.mkForce [
          "-device virtio-net-pci,netdev=user.0"
          "-netdev user,id=user.0,hostfwd=tcp::2224-:2222"
        ];
      };
    };
  };
}
