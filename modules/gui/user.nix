{ config, lib, pkgs, inputs, ... }:

{ 
  imports = [
    inputs.impermanence.nixosModules.home-manager.impermanence
  ];

  home.stateVersion = "23.11"; # Please read the comment before changing.

  home.persistence."/persist/home/erik" = {
    directories = [
      "Downloads"
      "Music"
      "Pictures"
      "Documents"
      "Videos"
      "VirtualBox VMs"
      ".gnupg"
      ".ssh"
      ".nixops"
      ".local/share/keyrings"
      ".local/share/direnv"
      ".local/state/wireplumber"
      { directory = ".config/BraveSoftware"; mode = "0700"; }
      {
        directory = ".local/share/Steam";
        method = "symlink";
      }
    ];
    files = [
      ".screenrc"
    ];
    allowOther = true;
  };
}
