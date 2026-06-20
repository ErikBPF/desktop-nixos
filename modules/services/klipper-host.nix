{
  self,
  config,
  ...
}: let
  inherit (config) domain; # flake-parts top-level option (meta.nix)
in {
  # Klipper print-host stack for the BIQU B1 (`archinaut`).
  #
  # Principle (see docs/proposals/2026-06-16-printer-nixos-host.md): NixOS owns
  # packages, services and MCU-firmware *builds* only. ALL printer config lives
  # in the klipper-biqu repo and is rsync-seeded into a MUTABLE configDir, so
  # SAVE_CONFIG + Mainsail edits survive. The one exception is moonraker.conf,
  # which the NixOS module renders from `settings` (declarative) — that file is
  # stable infra, not calibration.
  flake.modules.nixos.klipper-host = {
    pkgs,
    lib,
    config,
    ...
  }: let
    cfg = config.printer.haPower;
    configDir = "/var/lib/klipper";

    # §6a: stock klipper lacks the third-party klippy extras the printer.cfg
    # uses ([autotune_tmc], [motor_constants …]). Vendor them into the package.
    tmcAutotuneSrc = pkgs.fetchFromGitHub {
      owner = "andrewmcgr";
      repo = "klipper_tmc_autotune";
      rev = "aa26fc04f444997bd64b30a37414d678107cc04c";
      hash = "sha256-v+8VFkG9iJ43wbXVNpXzdA5sUnRQxhcJIxHPbNoBUp4=";
    };

    # shell_command.cfg needs the G-Code Shell Command extra ([gcode_shell_command])
    # for the `update_git` klipper-backup macro. Also not in stock klipper.
    gcodeShellCommandSrc = pkgs.fetchurl {
      name = "gcode_shell_command.py";
      url = "https://raw.githubusercontent.com/dw-0/kiauh/b90a8f13b198726bfb75d56a7e540e46c4011685/kiauh/extensions/gcode_shell_cmd/assets/gcode_shell_command.py";
      hash = "sha256-WTcKHi+2BNRnLBxBueJmkG5Zb9zfr+RvXPeQSJWEHSk=";
    };

    # Placeholder seed — klipper requires `configFile` or `settings`, but the
    # real config is rsync-seeded from the repo (`just seed-archinaut`) before
    # first start. With mutableConfig the seed is only used if printer.cfg is
    # absent; it is never written over the repo config.
    seedConfig = pkgs.writeText "printer.cfg" ''
      # Placeholder. Run `just seed-archinaut` to populate /var/lib/klipper from
      # the klipper-biqu repo. Klipper will not start usefully until then.
    '';
  in {
    # The HomeAssistant power plugin needs a moonraker secrets entry that only
    # exists once provisioned in sops. Off by default so the host builds clean;
    # flip it on (archinaut host module) AFTER adding `moonraker/secrets` to the
    # sops file and archinaut's host age key to .sops.yaml.
    options.printer.haPower.enable =
      lib.mkEnableOption "moonraker HomeAssistant power plugin ([power biqu])";

    config = {
      nixpkgs.overlays = [
        (_final: prev: {
          klipper = prev.klipper.overrideAttrs (old: {
            postInstall =
              (old.postInstall or "")
              + ''
                cp ${tmcAutotuneSrc}/autotune_tmc.py \
                   ${tmcAutotuneSrc}/motor_constants.py \
                   ${tmcAutotuneSrc}/motor_database.cfg \
                   $out/lib/klipper/extras/
                cp ${gcodeShellCommandSrc} $out/lib/klipper/extras/gcode_shell_command.py
              '';
          });
        })
      ];

      users.users.klipper = {
        isSystemUser = true;
        group = "klipper";
        # MCU is USB-serial on the SKR 1.4 → dialout for /dev/serial access.
        extraGroups = ["dialout"];
      };
      users.groups.klipper = {};

      services.klipper = {
        enable = true;
        user = "klipper";
        group = "klipper";
        mutableConfig = true; # repo-seeded printer.cfg persists; SAVE_CONFIG works
        inherit configDir;
        configFile = seedConfig;
        apiSocket = "/run/klipper/api";
      };

      services.moonraker = {
        enable = true;
        user = "klipper";
        group = "klipper";
        address = "0.0.0.0";
        port = 7125;
        allowSystemControl = true; # Mainsail restart/shutdown
        klipperSocket = config.services.klipper.apiSocket;
        settings =
          {
            server.enable_debug_logging = false;
            file_manager.enable_object_processing = true;
            authorization = {
              cors_domains = [
                "https://my.mainsail.xyz"
                "http://my.mainsail.xyz"
                "http://*.local"
                "http://*.lan"
              ];
              trusted_clients = [
                "10.0.0.0/8"
                "127.0.0.0/8"
                "169.254.0.0/16"
                "172.16.0.0/12"
                "192.168.0.0/16"
                "FE80::/10"
                "::1/128"
              ];
            };
            octoprint_compat = {};
            history = {};
            announcements.subscriptions = ["mainsail"];
            # NOTE: every [update_manager …] git_repo entry from the Debian conf
            # is intentionally dropped — NixOS owns versions; git updaters can't
            # run on a read-only store.
          }
          # HA zigbee plug (was [power biqu]). Opt-in: needs the sops secret.
          // lib.optionalAttrs cfg.enable {
            "power biqu" = {
              type = "homeassistant";
              protocol = "https";
              address = "ha.${domain}";
              port = 443;
              device = "switch.tomada_impressora_2";
              token = "{secrets.home_assistant.token}";
              domain = "switch";
              status_delay = 1.0;
              locked_while_printing = true;
              restart_klipper_when_powered = true;
              on_when_job_queued = true;
              bound_services = "klipper";
            };
            secrets.secrets_path = config.sops.secrets."moonraker/secrets".path;
          };
      };

      services.mainsail.enable = true;

      # Webcam — single Logitech C270 (replaces crowsnest). 720p MJPEG on :8080;
      # add the stream to Mainsail as http://<host>:8080/stream.
      systemd.services.ustreamer = {
        description = "ustreamer MJPEG stream (C270)";
        wantedBy = ["multi-user.target"];
        after = ["network.target"];
        serviceConfig = {
          ExecStart = lib.concatStringsSep " " [
            "${pkgs.ustreamer}/bin/ustreamer"
            "--device=/dev/video0"
            "--resolution=1280x720"
            "--format=MJPEG"
            "--host=0.0.0.0"
            "--port=8080"
          ];
          Restart = "always";
          RestartSec = "5s";
          DynamicUser = true;
          SupplementaryGroups = ["video"];
        };
      };

      # HA token for moonraker's [power biqu] (decrypted file is a moonraker
      # secrets ini: [home_assistant] token=…). Only declared when the plugin is
      # enabled — sops-nix validates secret presence at BUILD time, so declaring
      # it unconditionally blocks the build until the key exists in the sops file.
      sops.secrets = lib.mkIf cfg.enable {
        "moonraker/secrets" = {
          sopsFile = self + "/secrets/sops/secrets.yaml";
          owner = "klipper";
          group = "klipper";
        };
      };

      # klipper-backup (config → klipper-biqu git) is NOT in nixpkgs; it is cloned
      # under erik's home on the Pi post-boot, its PAT .env provisioned from sops.
      # See the RFC §5.4 / §8.

      networking.firewall.allowedTCPPorts = [80 7125 8080];
    };
  };
}
