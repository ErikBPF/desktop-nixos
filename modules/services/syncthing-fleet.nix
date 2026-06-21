{
  config,
  lib,
  ...
}: let
  deviceIDs = config.syncthingDeviceIDs;
  stignore = ../common/stignore;
  # State-mirror folders must sync *.tfstate etc., which the fleet-wide
  # stignore excludes — give them a no-op ignore file instead.
  stignoreSyncAll = ../common/stignore-sync-all;
  u = config.username;

  folderLabels = {
    "ndykv-cjhly" = "Downloads";
    "ykxhp-khmz2" = "Documents";
    "xbwsp-zwvsr" = "kube";
    "tofu-state" = "tofu-state-iac";
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
        "tofu-state" = {
          path = "/home/${u}/tofu-state-backup/";
          devices = ["discovery" "kepler"];
          versioning = {
            type = "staggered";
            params.maxAge = toString (30 * 24 * 3600);
          };
        };
      };
    };
    # discovery holds the fleet backup copies under ~/backup (note: kube,
    # not .kube — the backup copy is kept visible).
    discovery = {
      # kepler is in `devices` (connection) but NOT `shareWith`: only the
      # tofu-state folder reaches it, the user backup folders do not.
      devices = ["laptop" "pathfinder" "orion" "kepler"];
      shareWith = ["laptop" "pathfinder" "orion"];
      folderPaths = {
        "ndykv-cjhly" = "/home/${u}/backup/Downloads/";
        "ykxhp-khmz2" = "/home/${u}/backup/Documents/";
        "xbwsp-zwvsr" = "/home/${u}/backup/kube/";
        # OpenTofu state mirror (ciphertext) — discovery is the source of
        # truth; orion + kepler hold off-host copies. Populated by the
        # minio-tfstate-mirror container (servarr).
        "tofu-state" = {
          path = "/home/${u}/tofu-state-export/";
          devices = ["orion" "kepler"];
        };
      };
    };
    # kepler syncs no user folders yet.
    # /opt/models: AI model weights — sync to/from orion after first boot.
    # Kepler is the primary source; Orion is a consumer. Add a "models"
    # folder (path /fast/models, devices ["orion"]) once orion's syncthing
    # is updated to include it.
    kepler = {
      devices = ["discovery" "orion"];
      folderPaths = {
        "tofu-state" = {
          path = "/home/${u}/tofu-state-backup/";
          devices = ["discovery" "orion"];
          versioning = {
            type = "staggered";
            params.maxAge = toString (30 * 24 * 3600);
          };
        };
      };
    };
  };

  # A folder entry is either a path string (shared with the host's `shareWith`
  # peers) or `{ path; devices; }` to target specific peers — e.g. the
  # tofu-state backup goes only to orion+kepler, not to the laptop/pathfinder
  # the user folders share with.
  folderPathOf = spec:
    if builtins.isAttrs spec
    then spec.path
    else spec;

  mkHostModule = name: {
    devices,
    folderPaths,
    shareWith ? devices,
  }: _: let
    # Create dirs only for explicitly-targeted folders; the string folders
    # (Downloads/Documents/kube) already exist under $HOME, so leave them be.
    targetedDirs =
      map (spec: spec.path)
      (lib.filter builtins.isAttrs (builtins.attrValues folderPaths));
  in {
    systemd.tmpfiles.rules =
      (map (p: "d ${p} 0700 ${u} users - -") targetedDirs)
      ++ (lib.mapAttrsToList
        (_: spec: "L+ ${folderPathOf spec}.stignore - - - - ${
          if builtins.isAttrs spec
          then stignoreSyncAll
          else stignore
        }")
        folderPaths);

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
        folders = lib.mapAttrs (id: spec:
          {
            label = folderLabels.${id};
            path = folderPathOf spec;
            devices =
              if builtins.isAttrs spec && spec ? devices
              then spec.devices
              else shareWith;
          }
          # Receivers keep version history so an upstream corruption/wipe
          # doesn't silently overwrite the only off-host copy.
          // lib.optionalAttrs (builtins.isAttrs spec && spec ? versioning) {
            inherit (spec) versioning;
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
