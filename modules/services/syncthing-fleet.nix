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

  # 30-day staggered history on receiver copies of a state mirror.
  stateVersioning = {
    type = "staggered";
    params.maxAge = toString (30 * 24 * 3600);
  };

  # A folder entry in the topology is either a path string (the common case:
  # shared with the host's `shareWith` peers, fleet stignore, dir assumed to
  # already exist under $HOME) or an attrset overriding any of those fields.
  # Normalize both to one record up front so nothing downstream branches on the
  # spec's shape. Attrset folders default to syncAll + ensureDir — they're
  # purpose-built dirs (e.g. the tofu-state mirror) that must replicate
  # *.tfstate (which the fleet stignore excludes) and be created by tmpfiles.
  folderDefaults = {
    devices = null; # null → fall back to the host's shareWith
    versioning = null; # null → no version history
    syncAll = false; # true → stignore-sync-all instead of the fleet stignore
    ensureDir = false; # true → tmpfiles creates the dir
  };
  normalizeFolder = spec:
    if builtins.isString spec
    then folderDefaults // {path = spec;}
    else
      folderDefaults
      // {
        syncAll = true;
        ensureDir = true;
      }
      // spec;

  folderLabels = {
    "ndykv-cjhly" = "Downloads";
    "ykxhp-khmz2" = "Documents";
    "xbwsp-zwvsr" = "kube";
    "tofu-state" = "tofu-state-iac";
    "dev-workspace" = "dev-workspace";
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
      devices = ["discovery" "pathfinder" "orion" "gemini"];
      folderPaths = {
        "ndykv-cjhly" = "/home/${u}/Downloads/";
        "ykxhp-khmz2" = "/home/${u}/Documents/";
        "xbwsp-zwvsr" = "/home/${u}/.kube/";
        # Mirror of the orion dev-sandbox (gemini) workspace — remote-primary
        # (edit on gemini), the laptop keeps an offline/backup copy.
        "dev-workspace" = {
          path = "/home/${u}/dev/";
          devices = ["gemini"];
        };
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
          versioning = stateVersioning;
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
          versioning = stateVersioning;
        };
      };
    };
    # gemini — the orion dev-sandbox container. Its own tailnet node; syncs only
    # the dev workspace with the laptop. (Generated module consumed by the
    # container config in modules/hosts/orion/gemini.nix.)
    gemini = {
      devices = ["laptop"];
      folderPaths = {
        # Full Documents + Downloads mirror from the laptop (repos incl .git —
        # see the stignore note). dev-workspace kept for scratch.
        "ndykv-cjhly" = "/home/${u}/Downloads/";
        "ykxhp-khmz2" = "/home/${u}/Documents/";
        "dev-workspace" = {
          path = "/home/${u}/dev/";
          devices = ["laptop"];
        };
      };
    };
  };

  mkHostModule = name: {
    devices,
    folderPaths,
    shareWith ? devices,
  }: _: let
    folders = lib.mapAttrs (_: normalizeFolder) folderPaths;
  in {
    systemd.tmpfiles.rules =
      (lib.mapAttrsToList (_: f: "d ${f.path} 0700 ${u} users - -")
        (lib.filterAttrs (_: f: f.ensureDir) folders))
      ++ (lib.mapAttrsToList
        (_: f: "L+ ${f.path}.stignore - - - - ${
          if f.syncAll
          then stignoreSyncAll
          else stignore
        }")
        folders);

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
        folders = lib.mapAttrs (id: f:
          {
            label = folderLabels.${id};
            inherit (f) path;
            devices =
              if f.devices != null
              then f.devices
              else shareWith;
          }
          # Receivers keep version history so an upstream corruption/wipe
          # doesn't silently overwrite the only off-host copy.
          // lib.optionalAttrs (f.versioning != null) {
            inherit (f) versioning;
          })
        folders;
      };
    };
  };
in {
  flake.modules.nixos =
    lib.mapAttrs'
    (name: spec: lib.nameValuePair "${name}-syncthing" (mkHostModule name spec))
    hosts;
}
