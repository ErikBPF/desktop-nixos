{ config, lib, inputs, pkgs, ... }:

{
  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
      timeout = 0;
    };
    kernelPackages = pkgs.linuxPackages_zen;
    kernelParams = [ "fastboot" ];
    consoleLogLevel = 3;
    initrd.verbose = false;
    initrd.systemd.enable = true;
    initrd.postDeviceCommands = lib.mkAfter ''
      mkdir /btrfs_tmp
      mount /dev/root_vg/root /btrfs_tmp
      if [[ -e /btrfs_tmp/root ]]; then
          mkdir -p /btrfs_tmp/old_roots
          timestamp=$(date --date="@$(stat -c %Y /btrfs_tmp/root)" "+%Y-%m-%-d_%H:%M:%S")
          mv /btrfs_tmp/root "/btrfs_tmp/old_roots/$timestamp"
      fi

      delete_subvolume_recursively() {
          IFS=$'\n'
          for i in $(btrfs subvolume list -o "$1" | cut -f 9- -d ' '); do
              delete_subvolume_recursively "/btrfs_tmp/$i"
          done
          btrfs subvolume delete "$1"
      }

      for i in $(find /btrfs_tmp/old_roots/ -maxdepth 1 -mtime +30); do
          delete_subvolume_recursively "$i"
      done

      btrfs subvolume create /btrfs_tmp/root
      umount /btrfs_tmp
    '';
    plymouth.enable = false;
  };

  systemd.tmpfiles.rules = [
  "d /persist/home/ 0777 root root -" # create /persist/home owned by root
  "d /persist/home/erik 0700 erik users -" # /persist/home/erik owned by that user
  ];

  fileSystems."/persist".neededForBoot = true;
  environment.persistence."/persist/system" = {
   hideMounts = true;
   directories = [
     "/etc/nixos"
     "/var/log"
     "/var/lib/bluetooth"
     "/var/lib/nixos"
     "/var/lib/systemd/coredump"
     "/etc/NetworkManager/system-connections"
     { directory = "/var/lib/colord"; user = "colord"; group = "colord"; mode = "u=rwx,g=rx,o="; }
   ];
   files = [
     "/etc/machine-id"
     { file = "/var/keys/secret_file"; parentDirectory = { mode = "u=rwx,g=,o="; }; }
   ];
  };

  programs.fuse.userAllowOther = true;
  home-manager = {
   extraSpecialArgs = {inherit inputs;};
   users = {
     "erik" = import ./gui/user.nix;
   };
  };

  systemd.services = {
    NetworkManager-wait-online.enable = false;
    systemd-udev-settle.enable = false;
  };
  #systemd.targets.network-online.enable = false;
}
