{config, ...}: let
  deviceIDs = config.syncthingDeviceIDs;
in {
  flake.modules.nixos.pathfinder-syncthing = {config, ...}: let
    homeDir = "/home/erik";
  in {
    services.syncthing = {
      enable = false;
      guiAddress = "127.0.0.1:8384";
      openDefaultPorts = false;
      relay.enable = false;
      configDir = "${homeDir}/.config/syncthing";
      dataDir = "${homeDir}/.config/syncthing";
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
            path = "${homeDir}/Downloads/";
            devices = ["discovery" "archlinux"];
          };
          "ykxhp-khmz2" = {
            label = "Documents";
            path = "${homeDir}/Documents/";
            devices = ["discovery" "archlinux"];
          };
          "xbwsp-zwvsr" = {
            label = "kube";
            path = "${homeDir}/.kube/";
            devices = ["discovery" "archlinux"];
          };
        };
      };
    };
  };
}
