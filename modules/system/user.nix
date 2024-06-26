{ config, lib, pkgs, ... }:

{
  users.users.erik = {
    isNormalUser = true;
    shell = pkgs.nushell;
    description = "Erik Bogado";
    extraGroups = [ "networkmanager" "wheel" ];
  };

  programs.git.config = {
    user.name = "Erik Bogado";
    user.email = "test@test.com";
  };


  environment.persistence."/persist".users.erik = {
    directories = [
      "Dots/"
      "Code/"
      "Documents/"
      "Downloads/"
      ".local/share/nvim/"
      ".local/state/nvim/"
      ".local/share/zoxide/"
      ".cache/zellij/"
      ".cache/rclone/"
      { directory = ".config/syncthing"; mode = "0700"; }
      { directory = ".ssh"; mode = "0700"; }
    ];
    files = [
      ".config/nushell/history.txt"
    ];
  };

  security.sudo.extraRules = [{ users = [ "erik" ]; commands = [{ command = "/home/erik/.config/hypr/scripts/sync.nu"; options = [ "NOPASSWD" ]; }]; }];

  environment.sessionVariables = {
    FZF_DEFAULT_OPTS = ''--pointer=\" \" --prompt=\" \" --preview-window=border-none --info=hidden --color=fg:7,bg:0,hl:1,fg+:232,bg+:1,hl+:255,info:7,prompt:2,spinner:1,pointer:232,marker:1'';
    LS_COLORS = ":su=30;41:ow=30;42:st=30;44:";
  };
}
