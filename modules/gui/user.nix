{ config, lib, pkgs, ... }:

{
  # environment.persistence."/persist".users.erik = {
  #   directories = [
  #     ".cache/keepassxc"
  #     ".config/keepassxc"
  #     ".config/Logseq"
  #     # ".config/obsidian"
  #     # ".config/Nextcloud"
  #     ".local/state/wireplumber"
  #     { directory = ".config/BraveSoftware"; mode = "0700"; }
  #   ];
  # };

  #systemd.services.syncthing = {
  #  wantedBy = lib.mkForce [ "graphical.target" ];
  #  after = lib.mkForce ["graphical.target"];
  #};
  #systemd.services.syncthing-init.wantedBy = lib.mkForce [ "syncthing.service" ];
}
