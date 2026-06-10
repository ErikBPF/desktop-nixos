{
  config,
  lib,
  ...
}: let
  deviceIDs = config.syncthingDeviceIDs;
  stignore = ../common/stignore;
  u = config.username;

  folderLabels = {
    "ndykv-cjhly" = "Downloads";
    "ykxhp-khmz2" = "Documents";
    "xbwsp-zwvsr" = "kube";
  };

  # Per-host topology. `devices` are the peers this host connects to;
  # `shareWith` (defaults to `devices`) are the peers folders sync with —
  # orion also knows kepler for the future /fast/models folder but does not
  # share the user folders with it.
  hosts = {
    pathfinder = {
      devices = ["discovery" "laptop" "orion"];
      folderPaths = {
        "ndykv-cjhly" = "/home/${u}/Downloads/";
        "ykxhp-khmz2" = "/home/${u}/Documents/";
        "xbwsp-zwvsr" = "/home/${u}/.kube/";
      };
    };
    laptop = {
      devices = ["discovery" "pathfinder" "orion"];
      folderPaths = {
        "ndykv-cjhly" = "/home/${u}/Downloads/";
        "ykxhp-khmz2" = "/home/${u}/Documents/";
        "xbwsp-zwvsr" = "/home/${u}/.kube/";
      };
    };
    orion = {
      devices = ["discovery" "laptop" "pathfinder" "kepler"];
      shareWith = ["discovery" "laptop" "pathfinder"];
      folderPaths = {
        "ndykv-cjhly" = "/home/${u}/Downloads/";
        "ykxhp-khmz2" = "/home/${u}/Documents/";
        "xbwsp-zwvsr" = "/home/${u}/.kube/";
      };
    };
    # discovery holds the fleet backup copies under ~/backup (note: kube,
    # not .kube — the backup copy is kept visible).
    discovery = {
      devices = ["laptop" "pathfinder" "orion"];
      folderPaths = {
        "ndykv-cjhly" = "/home/${u}/backup/Downloads/";
        "ykxhp-khmz2" = "/home/${u}/backup/Documents/";
        "xbwsp-zwvsr" = "/home/${u}/backup/kube/";
      };
    };
    # kepler syncs no user folders yet.
    # /opt/models: AI model weights — sync to/from orion after first boot.
    # Kepler is the primary source; Orion is a consumer. Add a "models"
    # folder (path /fast/models, devices ["orion"]) once orion's syncthing
    # is updated to include it.
    kepler = {
      devices = ["discovery" "orion"];
      folderPaths = {};
    };
  };

  mkHostModule = name: {
    devices,
    folderPaths,
    shareWith ? devices,
  }: _: {
    systemd.tmpfiles.rules =
      map (path: "L+ ${path}.stignore - - - - ${stignore}")
      (builtins.attrValues folderPaths);

    services.syncthing = {
      enable = true;
      guiAddress = "127.0.0.1:8384";
      openDefaultPorts = false;
      relay.enable = false;
      configDir = "/home/${u}/.config/syncthing";
      dataDir = "/home/${u}/.config/syncthing";
      overrideDevices = true;
      overrideFolders = true;
      user = u;
      settings = {
        # TCP-only listeners — QUIC disabled fleet-wide as workaround for the
        # Go 1.26 TLS panic "crypto/tls bug: where's my session ticket?".
        # NixOS syncthing module uses the JSON API format, not XML:
        # XML rawListenAddresses → JSON API listenAddresses.
        options.listenAddresses = ["tcp://0.0.0.0:22000" "tcp://[::]:22000"];
        devices = lib.genAttrs devices (peer: {
          id = deviceIDs."${peer}_id";
          addresses = ["tcp://${peer}:22000" "dynamic"];
        });
        folders =
          lib.mapAttrs (id: path: {
            label = folderLabels.${id};
            inherit path;
            devices = shareWith;
          })
          folderPaths;
      };
    };
  };
in {
  flake.modules.nixos =
    lib.mapAttrs'
    (name: spec: lib.nameValuePair "${name}-syncthing" (mkHostModule name spec))
    hosts;
}
