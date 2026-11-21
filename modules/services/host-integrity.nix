_: {
  flake.modules.nixos.host-integrity = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.services.hostIntegrity;
    helpers = pkgs.linkFarm "host-integrity-helpers" [
      {
        name = "_host-integrity-run.py";
        path = ./_host-integrity-run.py;
      }
      {
        name = "_host-integrity-pilot.py";
        path = ./_host-integrity-pilot.py;
      }
      {
        name = "_host-integrity-report.py";
        path = ./_host-integrity-report.py;
      }
    ];
    database = "/var/lib/host-integrity/database";
    freshclam = pkgs.writeText "host-integrity-freshclam.conf" ''
      DatabaseOwner root
      DatabaseDirectory ${database}
      DatabaseMirror database.clamav.net
      Bytecode yes
    '';
    jobConfig = check: job:
      pkgs.writeText "host-integrity-${check}.json" (builtins.toJSON ({
          inherit check;
          instance = config.networking.hostName;
          state_dir = "/var/lib/host-integrity";
          metrics_dir = "/var/lib/host-integrity-metrics";
          databaseDirectory = database;
          work_dir = "/run/host-integrity-${check}";
          sourceRevision = builtins.hashString "sha256" (builtins.readFile ./_host-integrity-run.py + builtins.readFile ./_host-integrity-report.py + builtins.readFile ./_host-integrity-pilot.py + builtins.readFile ./host-integrity.nix);
          command =
            if check == "store"
            then ["${pkgs.nix}/bin/nix" "--offline" "--store" "daemon" "store" "verify" "--all" "--no-trust"]
            else if check == "signatures"
            then ["${pkgs.clamav}/bin/freshclam" "--config-file=${freshclam}"]
            else [
              "${pkgs.clamav}/bin/clamscan"
              "--no-summary"
              "--stdout"
              "--recursive=no"
              "--follow-file-symlinks=0"
              "--follow-dir-symlinks=0"
              "--cross-fs=no"
              "--tempdir=/run/host-integrity-av"
              "--alert-encrypted=yes"
              "--alert-exceeds-max=yes"
              "--max-filesize=${toString job.maxFileBytes}"
              "--max-scansize=${toString job.maxScanBytes}"
              "--max-files=${toString job.maxFiles}"
              "--max-recursion=${toString job.maxRecursion}"
            ];
        }
        // builtins.removeAttrs job ["calendar" "jitterSeconds" "cpuQuotaPercent" "memoryMaxBytes" "ioWeight" "nice"]));
    runCommand = check: job: "${pkgs.python3}/bin/python3 ${helpers}/_host-integrity-run.py --config ${jobConfig check job}";
    pilotCommand = "${pkgs.python3}/bin/python3 ${helpers}/_host-integrity-pilot.py";
    configFiles = lib.genAttrs (map (check: "host-integrity/${check}.json") cfg.checks) (name: let
      check = lib.removeSuffix ".json" (lib.removePrefix "host-integrity/" name);
    in {
      source =
        if cfg.jobs ? ${check}
        then jobConfig check cfg.jobs.${check}
        else
          pkgs.writeText "host-integrity-${check}-reporting.json" (builtins.toJSON {
            inherit check;
            instance = config.networking.hostName;
            state_dir = "/var/lib/host-integrity";
            metrics_dir = "/var/lib/host-integrity-metrics";
          });
    });
    positive = description:
      lib.mkOption {
        type = lib.types.ints.positive;
        inherit description;
      };
    jobType = lib.types.submodule {
      options = {
        coordinationLock = lib.mkOption {
          type = lib.types.nullOr (lib.types.strMatching "/run/.*");
          default = null;
          description = "Optional root-owned exclusion lock shared with an owning backup command.";
        };
        scopeId = lib.mkOption {
          type = lib.types.strMatching "[a-z0-9][a-z0-9-]{0,63}";
          description = "Reviewed scope identifier.";
        };
        paths = lib.mkOption {
          type = lib.types.listOf (lib.types.strMatching "/.*");
          description = "Explicit local AV scope; empty for other checks.";
        };
        calendar = lib.mkOption {
          type = lib.types.nonEmptyStr;
          description = "Explicit systemd calendar schedule.";
        };
        jitterSeconds = positive "Maximum randomized timer delay in seconds.";
        timeoutSeconds = positive "Whole job deadline in seconds.";
        retentionDays = positive "Private receipt retention in days.";
        maxReceipts = positive "Maximum retained receipts per check.";
        maxFiles = positive "Scope entry and archive member limit.";
        maxRecursion = positive "Archive recursion limit.";
        maxFileBytes = positive "Maximum individual file bytes.";
        maxScanBytes = positive "Maximum expanded archive scan bytes.";
        maxTotalBytes = positive "Maximum total staged bytes.";
        outputMaxBytes = positive "Maximum captured subprocess output bytes.";
        cpuQuotaPercent = positive "Finite service CPU quota percentage.";
        memoryMaxBytes = positive "Finite service memory ceiling in bytes.";
        ioWeight = lib.mkOption {
          type = lib.types.ints.between 1 10000;
          description = "Service I/O scheduling weight.";
        };
        nice = lib.mkOption {
          type = lib.types.ints.between 0 19;
          description = "Service CPU scheduling niceness.";
        };
      };
    };
  in {
    options.services.hostIntegrity = {
      enable = lib.mkEnableOption "private persistent host integrity reporting";
      jobs = lib.mkOption {
        type = lib.types.attrsOf jobType;
        default = {};
        description = "Explicitly budgeted jobs; no timers or scans exist by default.";
      };
      checks = lib.mkOption {
        type = lib.types.listOf (lib.types.enum ["signatures" "store" "av"]);
        default = [];
        description = "Explicitly configured checks; no host is enrolled by default.";
      };
    };
    config = lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = config.services.alloy.enable && cfg.checks != [] && lib.unique cfg.checks == cfg.checks;
          message = "Host integrity requires Alloy and a nonempty unique check list.";
        }
        {
          assertion = lib.all (check: builtins.elem check cfg.checks && builtins.elem check ["store" "signatures" "av"]) (builtins.attrNames cfg.jobs);
          message = "Integrity jobs must be configured reporting checks.";
        }
        {
          assertion = lib.all (check:
            if check == "av"
            then cfg.jobs.${check}.paths != []
            else cfg.jobs.${check}.paths == []) (builtins.attrNames cfg.jobs);
          message = "AV requires explicit scope paths; other integrity jobs require an empty path list.";
        }
      ];
      environment.systemPackages = [
        (pkgs.writeShellScriptBin "host-integrity-pilot" ''
          exec ${pilotCommand} "$@"
        '')
      ];
      systemd.timers = lib.mapAttrs' (check: job:
        lib.nameValuePair "host-integrity-${check}" {
          wantedBy = ["timers.target"];
          timerConfig = {
            OnCalendar = job.calendar;
            RandomizedDelaySec = job.jitterSeconds;
            Persistent = true;
          };
        })
      cfg.jobs;
      systemd.services = lib.mkMerge [
        (lib.mkIf (cfg.jobs ? store) {
          host-integrity-store-preflight = {
            description = "Read-only Nix daemon query in the store verification sandbox";
            inherit (config.systemd.services.host-integrity-store) environment after;
            serviceConfig =
              config.systemd.services.host-integrity-store.serviceConfig
              // {
                ExecStart = "${pkgs.nix}/bin/nix --offline --store daemon path-info /run/current-system";
              };
          };
        })
        (lib.mkIf (cfg.jobs ? av) {
          "host-integrity-av-canary@" = {
            description = "Operator-only synthetic integrity canary %i";
            inherit (config.systemd.services.host-integrity-av) environment after onFailure;
            serviceConfig =
              config.systemd.services.host-integrity-av.serviceConfig
              // {
                ExecStart = "${pilotCommand} canary --config ${jobConfig "av" cfg.jobs.av} --case %i";
              };
          };
        })
        (lib.mapAttrs' (check: job:
          lib.nameValuePair "host-integrity-${check}" {
            description = "Bounded host integrity ${check}";
            environment.TMPDIR = "/run/host-integrity-${check}";
            after = ["systemd-tmpfiles-setup.service" "host-integrity-report.service"];
            onFailure = ["host-integrity-${check}-failure.service"];
            serviceConfig = {
              Type = "oneshot";
              User = "root";
              UMask = "0077";
              ExecStart = runCommand check job;
              RuntimeDirectory = "host-integrity-${check}";
              RuntimeDirectoryMode = "0700";
              TimeoutStartSec = job.timeoutSeconds + 30;
              TimeoutStopSec = "10s";
              KillMode = "control-group";
              CPUQuota = "${toString job.cpuQuotaPercent}%";
              MemoryMax = job.memoryMaxBytes;
              IOWeight = job.ioWeight;
              Nice = job.nice;
              NoNewPrivileges = true;
              ProtectSystem = "strict";
              ProtectHome = "read-only";
              PrivateTmp = check != "av";
              ReadWritePaths = ["/var/lib/host-integrity" "/var/lib/host-integrity-metrics"] ++ lib.optional (job.coordinationLock != null) (builtins.dirOf job.coordinationLock);
            };
          })
        cfg.jobs)
        (lib.mapAttrs' (check: job:
          lib.nameValuePair "host-integrity-${check}-failure" {
            description = "Publish host integrity ${check} unit failure";
            serviceConfig = {
              Type = "oneshot";
              User = "root";
              UMask = "0077";
              ExecStart = "${runCommand check job} --service-result unit-failed";
              TimeoutStartSec = "30s";
              TimeoutStopSec = "10s";
              CPUQuota = "${toString job.cpuQuotaPercent}%";
              MemoryMax = job.memoryMaxBytes;
              IOWeight = job.ioWeight;
              Nice = job.nice;
              NoNewPrivileges = true;
            };
          })
        cfg.jobs)
        {
          host-integrity-report = {
            description = "Restore persistent host integrity gauges";
            wantedBy = ["multi-user.target"];
            before = ["alloy.service"];
            after = ["systemd-tmpfiles-setup.service"];
            serviceConfig = {
              Type = "oneshot";
              User = "root";
              UMask = "0077";
              NoNewPrivileges = true;
              ProtectSystem = "strict";
              ProtectHome = true;
              PrivateTmp = true;
              ReadWritePaths = ["/var/lib/host-integrity" "/var/lib/host-integrity-metrics"];
              TimeoutStartSec = "30s";
            };
            script =
              lib.concatMapStringsSep "\n" (check: ''
                ${pkgs.python3}/bin/python3 ${./_host-integrity-report.py} \
                  --state-dir /var/lib/host-integrity \
                  --metrics-dir /var/lib/host-integrity-metrics \
                  --instance ${lib.escapeShellArg config.networking.hostName} \
                  --check ${lib.escapeShellArg check}
              '')
              cfg.checks;
          };
        }
      ];
      systemd.tmpfiles.rules = [
        "d /var/lib/host-integrity 0700 root root - -"
        "d ${database} 0700 root root - -"
        "d /var/lib/host-integrity-metrics 0755 root root - -"
      ];
      environment.etc =
        configFiles
        // {
          "alloy/config.alloy".text = lib.mkAfter ''
            // This root-owned input is independent of legacy user-writable metrics.
            prometheus.exporter.unix "host_integrity" {
              set_collectors = ["textfile"]
              textfile {
                directory = "/var/lib/host-integrity-metrics"
              }
            }
            prometheus.scrape "host_integrity" {
              targets         = prometheus.exporter.unix.host_integrity.targets
              forward_to      = [prometheus.relabel.host_integrity.receiver]
              scrape_interval = "30s"
              honor_labels    = true
            }
            prometheus.relabel "host_integrity" {
              rule {
                source_labels = ["__name__"]
                regex         = "host_integrity_.*"
                action        = "keep"
              }
              rule {
                source_labels = ["check"]
                regex         = "${lib.concatStringsSep "|" cfg.checks}"
                action        = "keep"
              }
              rule {
                target_label  = "instance"
                replacement   = "${config.networking.hostName}"
              }
              rule {
                regex         = "__name__|instance|check|job"
                action        = "labelkeep"
              }
              forward_to = [prometheus.remote_write.prometheus.receiver]
            }
          '';
        };
    };
  };
}
