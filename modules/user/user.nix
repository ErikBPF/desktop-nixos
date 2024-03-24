{ config, lib, pkgs, ... }:
{
  users.users.erik = {
    isNormalUser = true;
    initialPassword = "test";
    description = "Erik Bogado";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [
            firefox
            git
            #  thunderbird
            ];
  };

  programs.git.config = {
    user.name = "Erik Bogado";
    user.email = "test@test.com";
  };
}