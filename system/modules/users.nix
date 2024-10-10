{ config, pkgs, ... }:

{
users.users.erik = {
     isNormalUser = true;
     shell = pkgs.zsh;
     extraGroups = [ 
     	"wheel" 
        "qemu"
        "kvm"
        "libvirtd"
        "networkmanager"
     ]; 
   };
}
