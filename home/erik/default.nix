{
  inputs,
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [
    # inputs.sops-nix.nixosModules.sops
  ];
  home.username = "erik";
  home.homeDirectory = "/home/erik";
  home.stateVersion = "25.05";

  programs.home-manager.enable = true;

  programs.ssh = {
    enable = true;
    # extraConfig = ''
    #   Host *
    #     IdentityAgent ~/.1password/agent.sock
    # '';
  };

  programs.git = {
    enable = true;
    userName = "Erik Bogado";
    userEmail = "erikbogado@gmail.com";
    extraConfig = {
      credential.helper = "store";
    };
  };

  programs.bash = {
    enable = true;
    shellAliases = {
      btw = "echo i use nixos btw";
      nrs = "sudo nixos-rebuild switch";
      k = "kubectl";
      dc = "docker compose";
      urldecode = "python3 -c 'import sys, urllib.parse as ul; print(ul.unquote_plus(sys.stdin.read()))'";
      urlencode = "python3 -c 'import sys, urllib.parse as ul; print(ul.quote_plus(sys.stdin.read()))'";
    };

    initExtra = ''
      export PS1='\[\e[38;5;76m\]\u\[\e[0m\] in \[\e[38;5;32m\]\w\[\e[0m\] \\$ '
    '';
  };

  programs.alacritty = {
    enable = true;
    settings = {
      window.opacity = 0.9;
      font.normal = {
        family = "JetBrains Mono";
        style = "Regular";
      };
      font.size = 16;
    };
  };

  sops.age.keyFile = "/home/erik/.config/sops/age/keys.txt";
  sops.secrets = {
    password ={
      sopsFile = ../../secrets/secrets.yaml;
    };
    };

  home.file = {
  ".config/bat/config".text = ''
    --theme="Nord"
    --style="numbers,changes,grid"
    --paging=auto
  '';
  ".ssh/id_ed25519" = {
    text = "${config.sops.secrets.password.path}";
    onChange = ''
        sudo chmod 0400 ~/.ssh/id_ed25519
      '';

    #     ".ssh/dummy" = {
    #   text = "dummy";
    #   onChange = ''
    #     cp /mnt/c/Users/MyUserName/.ssh/id_* ~/.ssh/
    #     chmod 0400 ~/.ssh/id_*
    #   '';
    # };
  };
  };
}
