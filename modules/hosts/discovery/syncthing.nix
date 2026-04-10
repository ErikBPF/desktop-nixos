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
          "laptop" = {id = deviceIDs.laptop_id; addresses = ["tcp://laptop:22000" "dynamic"];};
          "pathfinder" = {id = deviceIDs.pathfinder_id; addresses = ["tcp://pathfinder:22000" "dynamic"];};
          "orion" = {id = deviceIDs.orion_id; addresses = ["tcp://orion:22000" "dynamic"];};
        };
        folders = {
          "ndykv-cjhly" = {
            label = "Downloads";
            path = "/home/erik/backup/Downloads/";
            devices = ["laptop" "pathfinder" "orion"];
          };
          "ykxhp-khmz2" = {
            label = "Documents";
            path = "/home/erik/backup/Documents/";
            devices = ["laptop" "pathfinder" "orion"];
          };
          "xbwsp-zwvsr" = {
            label = "kube";
            path = "/home/erik/backup/kube/";
            devices = ["laptop" "pathfinder" "orion"];
          };
        };
      };
    };
  };
}
