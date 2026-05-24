_: {
  # Global kernel tuning applied to every host.
  # Heavier per-host tuning (pcie_aspm, THP, swappiness, governor) lives next
  # to the host module that needs it.
  flake.modules.nixos.kernel-tuning = _: {
    boot.kernel.sysctl = {
      # Keep filesystem cache resident longer. Default is 100; lower values
      # bias the kernel toward reclaiming inode/dentry pages last. Speeds up
      # repeated file access (model loads, nix store walks, btrfs metadata).
      "vm.vfs_cache_pressure" = 50;
    };
  };
}
