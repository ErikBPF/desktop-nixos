{ config, lib, pkgs, ... }:

{
  environment.persistence."/perm".erik.mrb = {
    directories = [
      ".cache/keepassxc"
      ".config/keepassxc"
      ".config/Logseq"
      # ".config/obsidian"
      # ".config/Nextcloud"
      ".local/state/wireplumber"
      { directory = ".config/BraveSoftware"; mode = "0700"; }
    ];
  };
}
