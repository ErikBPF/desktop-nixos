{pkgs, ...}: {
  cli.programs.git.allowedSigners = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMxdE+uAvR4Nm2XwZNjTf2Ae8PlrRtnZUI6BBrbGl78u erikbogado@gmail.com";

  desktops = {
    hyprland = {
      enable = true;
      execOnceExtras = [
        "${pkgs.trayscale}/bin/trayscale"
      ];
    };
  };

  services.nixicle = {
    syncthing.enable = true;
  };

  roles = {
    desktop.enable = true;
    social.enable = true;
    gaming.enable = true;
    video.enable = true;
  };

  nixicle.user = {
    enable = true;
    name = "erik";
  };

  home.stateVersion = "23.11";
}
