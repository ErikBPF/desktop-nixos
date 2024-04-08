{ config, lib, pkgs, inputs, ... }:
{
  users.users.erik = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [
      "adbusers"
      "input"
      "libvirtd"
      "networkmanager"
      "plugdev"
      "transmission"
      "video"
      "wheel"
    ];
  };

  programs.git.config = {
    user.name = "erik";
    user.email = "erikbogado@gmail.com";
  };
  home.stateVersion = "23.11"; # Please read the comment before changing.
 
}
