{ config, lib, pkgs, ... }:

{
  hardware.opengl.driSupport32Bit = true;

  environment.systemPackages = with pkgs; [
    pkgsi686Linux.gperftools
  ];

  programs = {
    steam.enable = true;
  };

  # environment.persistence."/persist".users.erik = {
  #   directories = [
  #     ".local/share/Steam"
  #     ".cache/mesa_shader_cache"
  #   ];
  # };
}
