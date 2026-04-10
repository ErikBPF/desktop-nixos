{config, ...}: let
  deviceIDs = config.syncthingDeviceIDs;
in {
  flake.modules.nixos.laptop-syncthing = {config, ...}: let
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
        options = {
          # Disable QUIC — workaround for Go 1.26 TLS panic
          # "crypto/tls bug: where's my session ticket?"
          # NixOS syncthing module uses JSON API format, not XML format.
          # XML: rawListenAddresses → JSON API: listenAddresses
          listenAddresses = ["tcp://0.0.0.0:22000" "tcp://[::]:22000"];
        };
        devices = {
          "discovery" = {id = deviceIDs.discovery_id; addresses = ["tcp://discovery:22000" "dynamic"];};
          "pathfinder" = {id = deviceIDs.pathfinder_id; addresses = ["tcp://pathfinder:22000" "dynamic"];};
          "orion" = {id = deviceIDs.orion_id; addresses = ["tcp://orion:22000" "dynamic"];};
        };
        folders = {
          "ndykv-cjhly" = {
            label = "Downloads";
            path = "${homeDir}/Downloads/";
            devices = ["discovery" "pathfinder" "orion"];
          };
          "ykxhp-khmz2" = {
            label = "Documents";
            path = "${homeDir}/Documents/";
            devices = ["discovery" "pathfinder" "orion"];
          };
          "xbwsp-zwvsr" = {
            label = "kube";
            path = "${homeDir}/.kube/";
            devices = ["discovery" "pathfinder" "orion"];
          };
        };
      };
    };
  };
}
