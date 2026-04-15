{self, ...}: {
  flake.modules.nixos.laptop-ampagent = {
    config,
    pkgs,
    lib,
    ...
  }: let
    kaceHost = "kace.nstech.com.br";

    ampagentDeb = pkgs.requireFile {
      name = "ampagent-15.0.54.deb";
      sha256 = "1xn4pmwr33l9kmlis3nj3j89k718k58gcixhc800zrddb08m2ams";
      message = ''
        The Quest KACE AMP Agent .deb is required but not in the nix store.
        Run:  just add-ampagent
      '';
    };

    ampagent = pkgs.stdenv.mkDerivation {
      pname = "quest-kace-ampagent";
      version = "15.0.54";
      src = ampagentDeb;

      nativeBuildInputs = with pkgs; [dpkg autoPatchelfHook];
      buildInputs = [pkgs.stdenv.cc.cc.lib];

      dontConfigure = true;
      dontBuild = true;

      unpackPhase = "dpkg-deb -x $src .";

      installPhase = ''
        mkdir -p $out/bin $out/share/kace

        # Binaries
        cp -a opt/quest/kace/bin/* $out/bin/

        # Data files (cacert, modules, version)
        cp -r var/quest/kace/* $out/share/kace/
      '';
    };
  in {
    # Enrollment token from sops
    sops.secrets.kace_token = {
      sopsFile = self + "/secrets/sops/secrets.yaml";
    };

    # Mutable state directories
    systemd.tmpfiles.rules = [
      "d /var/quest/kace 0755 root root -"
      "d /var/quest/kace/user 0777 root root -"
      "d /usr/local/share/ca-certificates 0755 root root -"
    ];

    # amp.conf with KACE server host
    environment.etc."quest/kace/amp.conf" = {
      text = "host=${kaceHost}\n";
      mode = "0644";
    };

    # Write enrollment token and seed initial data
    system.activationScripts.kaceSetup = lib.stringAfter ["setupSecrets"] ''
      # Enrollment token from sops → sma.dat
      if [ -f "${config.sops.secrets.kace_token.path}" ]; then
        rm -f /var/quest/kace/sma.dat
        cp "${config.sops.secrets.kace_token.path}" /var/quest/kace/sma.dat
        chmod 0644 /var/quest/kace/sma.dat
      fi

      # Seed initial data (cacert, modules, version) — don't overwrite runtime state
      cp -rn "${ampagent}/share/kace/"* /var/quest/kace/ 2>/dev/null || true
      # Always keep version in sync with the package
      cp -f "${ampagent}/share/kace/version" /var/quest/kace/version

      ln -sfn /etc/quest/kace/amp.conf /var/quest/kace/amp.conf
    '';

    # konea — persistent tunnel/connection agent
    systemd.services.konea = {
      description = "Quest KACE Konea Agent";
      after = ["network-online.target"];
      wants = ["network-online.target"];
      wantedBy = ["multi-user.target"];

      path = with pkgs; [
        bash
        coreutils
        gnugrep
        gawk
        hostname
        iproute2
        dmidecode
        util-linux
        procps
        nettools
        nssTools
      ];

      serviceConfig = {
        Type = "simple";
        ExecStartPre = "-${pkgs.coreutils}/bin/rm -f /var/quest/kace/KONEA_STARTED";
        ExecStart = "${ampagent}/bin/konea -datadir /var/quest/kace";
        Restart = "on-failure";
        RestartSec = 30;
        WorkingDirectory = "/var/quest/kace";
      };
    };

    # KSchedulerConsole — task scheduler/inventory agent
    systemd.services.ampagent = {
      description = "Quest KACE AMP Agent";
      after = ["network-online.target" "konea.service"];
      wants = ["network-online.target" "konea.service"];
      wantedBy = ["multi-user.target"];

      path = with pkgs; [coreutils procps gnugrep gawk];

      serviceConfig = {
        Type = "forking";
        ExecStart = "${ampagent}/bin/KSchedulerConsole --daemon";
        ExecStop = pkgs.writeShellScript "ampagent-stop" ''
          killall -s SIGKILL KSchedulerConsole 2>/dev/null || true
        '';
        Restart = "on-failure";
        RestartSec = 30;
        WorkingDirectory = "/var/quest/kace";
      };
    };

    # AMPWatchDog — periodic health check
    systemd.services.ampagent-watchdog = {
      description = "Quest KACE AMP WatchDog";
      after = ["ampagent.service"];
      wants = ["ampagent.service"];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${ampagent}/bin/AMPWatchDog";
        WorkingDirectory = "/var/quest/kace";
      };
    };

    systemd.timers.ampagent-watchdog = {
      description = "Quest KACE AMP WatchDog Timer";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "15min";
      };
    };
  };
}
