{ config, lib, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ./modules 
  ];


  system.stateVersion = "23.11"; 
}

