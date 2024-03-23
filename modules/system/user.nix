{ config, lib, pkgs, ... }:

let secrets = builtins.fromTOML (builtins.readFile "/tmp/secrets.toml"); in
{
  users.users.erik = {
    isNormalUser = true;
    shell = pkgs.nushell;
    description = "Erik Bogado";
    extraGroups = [ "networkmanager" "wheel" ];
  };

  programs.git.config = {
    user.name = "Erik Bogado";
    user.email = secrets.misc.email;
  };

  # services.syncthing = {
  #   enable = true;
  #   user = "erik";
  #   configDir = "/home/erik/.config/syncthing";
  #   overrideDevices = true;
  #   overrideFolders = true;
  #   settings = {
  #     devices = {
  #       "Phone" = { id = secrets.syncthing.phone; };
  #     };
  #     folders = {
  #       "Documents" = {
  #         path = "/home/erik/Documents";
  #         devices = [ "Phone" ];
  #       };
  #       "Code" = {
  #         path = "/home/erik/Code";
  #         devices = [ "Phone" ];
  #       };
  #       "Downloads" = {
  #         path = "/home/erik/Downloads";
  #         devices = [ "Phone" ];
  #       };
  #     };
  #   };
  # };

  environment.persistence."/perm".users.erik = {
    directories = [
      "Dots/"
      "Code/"
      "Documents/"
      "Camera/"
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
