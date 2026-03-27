{config, ...}: let
  secrets = config.secrets;
in {
  flake.modules.nixos.discovery-syncthing = {...}: {
    services.syncthing = {
      enable = true;
      guiAddress = "127.0.0.1:8384";
      openDefaultPorts = false;
      relay.enable = false;
      configDir = "/home/erik/.config/syncthing";
      dataDir = "/home/erik/.config/syncthing";
      overrideDevices = true;
      overrideFolders = true;
      user = "erik";
      settings = {
        devices = {
          "Moon".id = secrets.syncthing.moon_id;
          "archlinux".id = secrets.syncthing.archlinux_id;
        };
        folders = {
          "ndykv-cjhly" = {
            label = "Downloads-backup";
            path = "/data/backup/Downloads/";
            devices = ["Moon" "archlinux"];
          };
          "ykxhp-khmz2" = {
            label = "Documents-backup";
            path = "/data/backup/Documents/";
            devices = ["Moon" "archlinux"];
          };
          "xbwsp-zwvsr" = {
            label = "kube-backup";
            path = "/data/backup/kube/";
            devices = ["Moon" "archlinux"];
          };
        };
      };
    };
  };
}
