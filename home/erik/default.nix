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

  xdg = {
    enable = true;
    userDirs = {
      enable = true;
      createDirectories = true;
    };
  };

  programs.home-manager.enable = true;

  programs.ssh = {
    enable = true;
  };

  programs.git = {
    enable = true;
    userName = "Erik Bogado";
    userEmail = "erikbogado@gmail.com";
    extraConfig = {
      credential.helper = "store";
    };
  };

  programs = {
    command-not-found.enable = false; # Required for fish
  };

  programs.nix-index = {
    enable = true;
    enableFishIntegration = true;
  };

  sops = {
    age = {
      keyFile = "/home/erik/.config/sops/age/keys.txt";
      generateKey = true;
    };
    defaultSopsFormat = "yaml";
    defaultSopsFile = ../../secrets/secrets.yaml;
    secrets = {
      password = {};
      id_ed25519 = {};
      id_rsa = {};
    };
  };

  home.file = {
    ".config/bat/config".text = ''
      --theme="Nord"
      --style="numbers,changes,grid"
      --paging=auto
    '';
    ".ssh/sops/ro_id_ed25519" = {
      source = config.sops.secrets.id_ed25519.path;
      onChange = ''
        cp ~/.ssh/sops/ro_id_ed25519 ~/.ssh/id_ed25519
        chmod 0400 ~/.ssh/id_ed25519
      '';
    };
    ".ssh/sops/ro_id_rsa" = {
      source = config.sops.secrets.id_rsa.path;
      onChange = ''
        cp ~/.ssh/sops/ro_id_rsa ~/.ssh/id_rsa
        chmod 0400 ~/.ssh/id_rsa
      '';
    };
    #     ".ssh/dummy" = {
    #   text = "dummy";
    #   onChange = ''
    #     cp /mnt/c/Users/MyUserName/.ssh/id_* ~/.ssh/
    #     chmod 0400 ~/.ssh/id_*
    #   '';
    # };
  };
}
