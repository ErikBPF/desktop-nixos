{config, ...}: let
  deviceIDs = config.syncthingDeviceIDs;
in {
  flake.modules.nixos.orion-syncthing = {config, ...}: let
    homeDir = "/home/erik";
  in {
    services.syncthing = {
      enable = true;
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
          "discovery" = {id = deviceIDs.discovery_id; addresses = ["tcp://discovery:22000" "dynamic"];};
          "laptop" = {id = deviceIDs.laptop_id; addresses = ["tcp://laptop:22000" "dynamic"];};
          "pathfinder" = {id = deviceIDs.pathfinder_id; addresses = ["tcp://pathfinder:22000" "dynamic"];};
          "kepler" = {id = deviceIDs.kepler_id; addresses = ["tcp://kepler:22000" "dynamic"];};
        };
        folders = {
          "ndykv-cjhly" = {
            label = "Downloads";
            path = "${homeDir}/Downloads/";
            devices = ["discovery" "laptop" "pathfinder"];
          };
          "ykxhp-khmz2" = {
            label = "Documents";
            path = "${homeDir}/Documents/";
            devices = ["discovery" "laptop" "pathfinder"];
          };
          "xbwsp-zwvsr" = {
            label = "kube";
            path = "${homeDir}/.kube/";
            devices = ["discovery" "laptop" "pathfinder"];
          };
        };
      };
    };
  };
}
