{config, ...}: let
  deviceIDs = config.syncthingDeviceIDs;
in {
  flake.modules.nixos.kepler-syncthing = {config, ...}: let
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
          "discovery".id = deviceIDs.discovery_id;
          "orion".id = deviceIDs.orion_id;
        };
        folders = {
          # /opt/models: AI model weights — sync to/from orion after first boot.
          # Kepler is the primary source; Orion is a consumer.
          # Uncomment once orion's syncthing is updated to include this folder.
          # "models" = {
          #   label = "models";
          #   path = "/fast/models";
          #   devices = ["orion"];
          # };
        };
      };
    };
  };
}
