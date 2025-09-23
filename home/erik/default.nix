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
  home.enableNixpkgsReleaseCheck = false;

  xdg = {
    enable = true;
    userDirs = {
      enable = true;
      createDirectories = true;
    };
  };

  programs.home-manager.enable = true;

  # programs.ssh = {
  #   enable = true;
  # };

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
      --style="numbers,changes,grid"
      --paging=auto
    '';
    # ".config/gtk-3.0/settings.ini".text = ''
    # [Settings]
    # gtk-theme-name=Tokyonight-Dark-B
    # gtk-icon-theme-name=Papirus-Dark
    # gtk-cursor-theme-name=Bibata-Modern-Ice
    # gtk-application-prefer-dark-theme=true
    # gtk-cursor-theme-size=24
    # '';
    # ".config/gtk-4.0/settings.ini".text = ''
    # [Settings]
    # gtk-theme-name=Tokyonight-Dark-B
    # gtk-icon-theme-name=Papirus-Dark
    # gtk-cursor-theme-name=Bibata-Modern-Ice
    # gtk-cursor-theme-size=24
    # gtk-application-prefer-dark-theme=true
    # '';
    ".config/qt6ct/qt6ct.conf".text = ''
    [Appearance]
    style=adwaita-dark
    icon_theme=Papirus-Dark
    standard_dialogs=gtk3
    palette=
    [Fonts]
    fixed=@Variant(\0\0\0\x7f\0\0\0\n\0M\0o\0n\0o\0s\0p\0a\0c\0e\0\0\0\0\0\0\0\0\0\x1e\0\0\0\0\0\0\0\0\0\0\0\0\0\0)
    general=@Variant(\0\0\0\x7f\0\0\0\n\0I\0n\0t\0e\0r\0\0\0\0\0\0\0\0\0\x1e\0\0\0\0\0\0\0\0\0\0\0\0\0\0)
    [Interface]
    double_click_interval=400
    cursor_flash_time=1000
    buttonbox_layout=0
    keyboard_scheme=2
    gui_effects=@Invalid()
    wheel_scroll_lines=3
    resolve_symlinks=true
    single_click_activate=false
    tabs_behavior=0
    [SettingsWindow]
    geometry=@ByteArray(AdnQywADAAAAAAAAB3wAAAQqAAAADwAAAB9AAAAEKgAAAA8AAAAAAAEAAAHfAAAAAQAAAAQAAAAfAAAABCg=)
    [Troubleshooting]
    force_raster_widgets=false
    ignore_platform_theme=false
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
