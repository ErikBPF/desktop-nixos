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
        # MCU is on the GPIO UART /dev/ttyS1 (mini-UART, GPIO14/15; ttyS0 is a
        # dead placeholder, ttyAMA0/PL011 needs disable-bt which breaks u-boot).
        # /dev/ttyS1 is group `dialout`, so klipper needs it.
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

      # The SoC thermal zone read by [temperature_sensor raspberry_pi] is
      # registered by bcm2835_thermal a few seconds into boot (it reads VC
      # firmware calibration). klippy hard-halts ("Unable to open temperature
      # file") if printer.cfg references thermal_zone0 before it exists, so wait
      # for it (bounded ~60s, then proceed regardless rather than block boot).
      systemd.services.klipper.preStart = ''
        n=0
        while [ ! -e /sys/class/thermal/thermal_zone0/temp ] && [ $n -lt 60 ]; do
          ${pkgs.coreutils}/bin/sleep 1
          n=$((n + 1))
        done
      '';

      # The Klipper MCU is powered by the printer PSU, independent of the Pi, so
      # it survives a host reboot and enters "shutdown" on lost comms. klippy
      # then reconnects to a shut-down MCU and stays in error until a
      # FIRMWARE_RESTART. (Power-sequencing used to dodge this by powering the
      # MCU only after the Pi was up; kernel-direct boot retired that.) Poll
      # klippy after boot and reset the MCU once if it comes up shut down, so the
      # printer reaches `ready` unattended.
      systemd.services.klipper-mcu-recover = {
        description = "FIRMWARE_RESTART the Klipper MCU if it is shut down after a host reboot";
        after = ["moonraker.service" "klipper.service"];
        wants = ["moonraker.service"];
        wantedBy = ["multi-user.target"];
        serviceConfig.Type = "oneshot";
        script = ''
          api=http://localhost:7125/printer
          n=0
          while [ $n -lt 60 ]; do
            info=$(${pkgs.curl}/bin/curl -fs "$api/info" 2>/dev/null || true)
            case "$info" in
              *'"state":"ready"'*) exit 0 ;;
              *shutdown*) ${pkgs.curl}/bin/curl -fs -X POST "$api/firmware_restart" >/dev/null 2>&1 || true; exit 0 ;;
            esac
            ${pkgs.coreutils}/bin/sleep 2
            n=$((n + 1))
          done
        '';
      };

      # Config backup → klipper-biqu, SAFE for the SHARED repo. klipper-backup's
      # own model wipes the whole repo (would delete orcaslicer/), so we don't
      # use it. Instead: reset a work clone to origin/main (preserving orcaslicer
      # and everything else), mirror /var/lib/klipper into printer_data/config/
      # ONLY, and commit/push just that subtree. SAVE_CONFIG + Mainsail edits thus
      # round-trip to git and survive a reflash. Pushes via the on-Pi deploy key
      # (write-scoped to klipper-biqu); reflash → regenerate it + re-add the
      # deploy key (see archinaut-kernel-direct memory). Runs as erik (owns the
      # key; /var/lib/klipper is world-readable).
      systemd.services.klipper-config-backup = {
        description = "Back up /var/lib/klipper to klipper-biqu (printer_data/config only — never touches orcaslicer/)";
        after = ["network-online.target"];
        wants = ["network-online.target"];
        path = [pkgs.git pkgs.rsync pkgs.openssh pkgs.coreutils];
        environment = {
          HOME = "/home/erik";
          GIT_SSH_COMMAND = "${pkgs.openssh}/bin/ssh -i /home/erik/.ssh/klipper_backup_deploy -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new";
        };
        serviceConfig = {
          Type = "oneshot";
          User = "erik";
        };
        script = ''
          set -euo pipefail
          work="$HOME/.cache/klipper-config-backup"
          repo="git@github.com:ErikBPF/klipper-biqu.git"
          [ -d "$work/.git" ] || git clone --depth 50 "$repo" "$work"
          cd "$work"
          git fetch -q origin main
          git checkout -q -B main origin/main
          mkdir -p printer_data/config
          rsync -a --delete --exclude=.git --exclude='*.swp' --exclude='*.tmp' \
            --exclude='*.bak' --exclude='printer-[0-9]*_[0-9]*.cfg' \
            /var/lib/klipper/ printer_data/config/
          git add printer_data/config
          if git diff --cached --quiet; then
            echo "no config changes"; exit 0
          fi
          git -c user.name=archinaut -c user.email=archinaut@pastelariadev \
            commit -q -m "auto: klipper config backup"
          git push -q origin main
        '';
      };
      systemd.timers.klipper-config-backup = {
        wantedBy = ["timers.target"];
        timerConfig = {
          OnCalendar = "daily";
          Persistent = true;
          RandomizedDelaySec = "30m";
        };
      };
      # Let Mainsail trigger a backup: klipper (via gcode_shell_command) may start
      # the unit. Scoped to this one unit, NOPASSWD.
      security.sudo.extraRules = [
        {
          users = ["klipper"];
          commands = [
            {
              command = "${pkgs.systemd}/bin/systemctl start klipper-config-backup.service";
              options = ["NOPASSWD"];
            }
          ];
        }
      ];

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
            # Declarative webcam — the C270 via raw ustreamer on :8080. Defined
            # here (not the moonraker DB) so a reflash reproduces it. A
            # config-defined webcam is read-only in the Mainsail UI.
            "webcam C270" = {
              location = "printer";
              service = "mjpegstreamer-adaptive";
              target_fps = 15;
              stream_url = "http://192.168.10.187:8080/stream";
              snapshot_url = "http://192.168.10.187:8080/snapshot";
            };
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

      # Webcam — single Logitech C270 (replaces crowsnest), MJPEG on :8080;
      # registered declaratively above (services.moonraker.settings."webcam C270").
      # 640x480: the RPi3's single USB 2.0 bus is shared with the onboard LAN
      # (LAN9514), and MJPEG 720p starved it → "uvcvideo: Failed to resubmit
      # video URB" + captured_fps 0. 480p fits the bandwidth. --persistent +
      # --device-timeout keep the stream alive across camera/USB hiccups.
      systemd.services.ustreamer = {
        description = "ustreamer MJPEG stream (C270)";
        wantedBy = ["multi-user.target"];
        after = ["network.target"];
        serviceConfig = {
          ExecStart = lib.concatStringsSep " " [
            "${pkgs.ustreamer}/bin/ustreamer"
            "--device=/dev/video0"
            "--resolution=640x480"
            "--format=MJPEG"
            "--desired-fps=15"
            "--persistent"
            "--device-timeout=8"
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
