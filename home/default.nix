{ config, pkgs, pkgs-unstable, lib, inputs, ... }:

{
  imports = [
    ./user
  ];
  
  home.username = "erik";
  home.homeDirectory = "/home/erik";
  home.stateVersion = "23.11";
}

