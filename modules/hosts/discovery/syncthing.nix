{config, ...}: let
  deviceIDs = config.syncthingDeviceIDs;
in {
  flake.modules.nixos.discovery-syncthing = _: {
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
        options.listenAddresses = ["tcp://0.0.0.0:22000" "tcp://[::]:22000"];
        devices = {
          "discovery".id = deviceIDs.discovery_id;
          "archlinux".id = deviceIDs.archlinux_id;
        };
        folders = {
          "ndykv-cjhly" = {
            label = "Downloads";
            path = "/data/backup/Downloads/";
            devices = ["discovery" "archlinux"];
          };
          "ykxhp-khmz2" = {
            label = "Documents";
            path = "/data/backup/Documents/";
            devices = ["discovery" "archlinux"];
          };
          "xbwsp-zwvsr" = {
            label = "kube";
            path = "/data/backup/kube/";
            devices = ["discovery" "archlinux"];
          };
        };
      };
    };
  };
}
