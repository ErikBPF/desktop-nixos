{self, ...}: {
  flake.modules.nixos.endeavour-trend = {
    config,
    pkgs,
    ...
  }: let
    ubuntuLsbRelease = pkgs.writeShellScriptBin "lsb_release" ''
      case "$1" in
        -i) echo "Distributor ID: Ubuntu" ;;
        -r) echo "Release: 24.04" ;;
        *) exit 1 ;;
      esac
    '';

    arch = pkgs.writeShellScriptBin "arch" ''
      exec ${pkgs.uutils-coreutils}/bin/uutils-arch "$@"
    '';

    ubuntuOsRelease = pkgs.writeText "ubuntu-os-release" ''
      NAME="Ubuntu"
      VERSION="24.04.2 LTS (Noble Numbat)"
      ID=ubuntu
      ID_LIKE=debian
      PRETTY_NAME="Ubuntu 24.04.2 LTS"
      VERSION_ID="24.04"
      VERSION_CODENAME=noble
      UBUNTU_CODENAME=noble
    '';

    systemctl = pkgs.writeShellScriptBin "systemctl" ''
      if [[ "$1" =~ ^(enable|start)$ && "$*" =~ (tmxbc|ds_agent) ]]; then
        exit 0
      fi
      exec ${pkgs.systemd}/bin/systemctl "$@"
    '';

    dpkg = pkgs.writeShellScript "dpkg" ''
      exec ${pkgs.dpkg}/bin/dpkg --force-depends "$@"
    '';

    ubuntuLibapt =
      pkgs.runCommand "ubuntu-libapt-pkg-6.0" {
        nativeBuildInputs = [pkgs.dpkg];
        src = pkgs.fetchurl {
          url = "https://archive.ubuntu.com/ubuntu/pool/main/a/apt/libapt-pkg6.0t64_2.7.14build2_amd64.deb";
          hash = "sha256-ORWwzfuq5VHZCJQA9HvnSbicMJFJhZgrOeV/0gFr6FI=";
        };
      } ''
        dpkg-deb -x "$src" unpacked
        mkdir -p "$out/lib"
        cp unpacked/usr/lib/x86_64-linux-gnu/libapt-pkg.so.6.0* "$out/lib/"
      '';

    agentLibraryPath = pkgs.lib.makeLibraryPath (with pkgs; [
      ubuntuLibapt
      stdenv.cc.cc.lib
      zlib
      bzip2
      xz
      lz4
      zstd
      systemd
      libgcrypt
      xxhash
    ]);

    installTrend = pkgs.writeShellScript "install-trend" ''
      set -euo pipefail
      installer=/run/trend-installer.sh
      trap 'rm -f "$installer"' EXIT
      tr -d '\r' < ${config.sops.secrets.trend-installer.path} |
        sed 's#/usr/bin/id#id#' > "$installer"
      chmod 0700 "$installer"
      bash "$installer"
    '';
  in {
    sops.secrets.trend-installer = {
      sopsFile = self + "/secrets/sops/trend-installer.sh";
      format = "binary";
      mode = "0400";
    };

    users.groups.tm_xes = {};
    users.groups.tm_dsa = {};

    systemd.services.tmxbc = {
      description = "Trend Micro Endpoint Basecamp";
      after = ["network-online.target"];
      wants = ["network-online.target"];
      wantedBy = ["multi-user.target"];
      path = with pkgs; [
        bash
        coreutils
        gnutar
        gzip
        xz
      ];
      unitConfig.ConditionPathExists = "/opt/TrendMicro/EndpointBasecamp/bin/tmxbc";
      serviceConfig = {
        Type = "simple";
        ExecStart = "/opt/TrendMicro/EndpointBasecamp/bin/tmxbc service run";
        Group = "tm_xes";
        Environment = "LD_LIBRARY_PATH=${agentLibraryPath}";
        BindReadOnlyPaths = [
          "${ubuntuOsRelease}:/etc/os-release"
          "${pkgs.dpkg}/bin/dpkg-deb:/usr/bin/dpkg-deb"
          "${dpkg}:/usr/bin/dpkg"
          "${pkgs.bash}/bin/bash:/bin/bash"
          "${pkgs.getent}/bin/getent:/usr/bin/getent"
          "${systemctl}/bin/systemctl:/bin/systemctl"
        ];
        Restart = "always";
        RestartSec = 3;
      };
    };

    systemd.services.ds_agent = {
      description = "Trend Micro Deep Security Agent";
      after = ["network-online.target"];
      wants = ["network-online.target"];
      wantedBy = ["multi-user.target"];
      unitConfig.ConditionPathExists = "/opt/ds_agent/ds_agent";
      serviceConfig = {
        Type = "forking";
        ExecStart = "/opt/ds_agent/ds_agent -w /var/opt/ds_agent -b -i -e /opt/ds_agent/ext";
        PIDFile = "/run/ds_agent.pid";
        Group = "tm_dsa";
        WorkingDirectory = "/opt/ds_agent";
        Environment = "LD_LIBRARY_PATH=${agentLibraryPath}";
        Restart = "on-failure";
        TimeoutSec = "5min";
        TasksMax = 1024;
        LimitNOFILE = 2048;
      };
    };

    systemd.paths.ds_agent = {
      wantedBy = ["multi-user.target"];
      pathConfig = {
        PathExists = "/opt/ds_agent/ds_agent";
        Unit = "ds_agent.service";
      };
    };

    systemd.services.trend-install = {
      description = "Install and enroll Trend Micro endpoint protection";
      after = ["network-online.target"];
      wants = ["network-online.target"];
      wantedBy = ["multi-user.target"];
      path = with pkgs; [
        arch
        ubuntuLsbRelease
        bash
        coreutils
        curl
        gnugrep
        gzip
        shadow
        systemctl
        gnutar
      ];
      unitConfig.ConditionPathExists = "!/opt/TrendMicro/EndpointBasecamp/etc/.identity";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = installTrend;
        BindReadOnlyPaths = "${ubuntuOsRelease}:/etc/os-release";
        TimeoutStartSec = "25min";
        RemainAfterExit = true;
      };
    };
  };
}
