{ config, lib, inputs, pkgs, ... }:

let secrets = builtins.fromTOML (builtins.readFile "/tmp/secrets.toml"); in
{

  users.users."erik" = {
    isNormalUser = true;
    initialPassword = "1045";
    extraGroups = [ "networkmanager" "wheel" ]; # Enable ‘sudo’ for the user.
    packages = with pkgs; [
       firefox
       vscodium
     ];

  programs.git.config = {
    user.name = "erik";
    user.email = "erikbogado@gmail.com";
  };

  security.sudo.extraRules = [{ users = [ "erik" ]; commands = [{ command = "/home/mrb/.config/hypr/scripts/sync.nu"; options = [ "NOPASSWD" ]; }]; }];

  environment.sessionVariables = {
    FZF_DEFAULT_OPTS = ''--pointer=\" \" --prompt=\" \" --preview-window=border-none --info=hidden --color=fg:7,bg:0,hl:1,fg+:232,bg+:1,hl+:255,info:7,prompt:2,spinner:1,pointer:232,marker:1'';
    LS_COLORS = ":su=30;41:ow=30;42:st=30;44:";
  };
}
