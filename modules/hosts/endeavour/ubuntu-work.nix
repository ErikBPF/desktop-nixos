_: {
  flake.modules.nixos.endeavour-ubuntu-work = {pkgs, ...}: let
    address = "192.168.122.74";
    mac = "52:54:00:3d:d6:e9";
    viewer = pkgs.writeShellApplication {
      name = "ubuntu-work-view";
      runtimeInputs = [pkgs.virt-viewer];
      text = ''
        exec virt-viewer --connect qemu:///system --reconnect --auto-resize=always --attach ubuntu-work
      '';
    };
    browser = pkgs.writeShellApplication {
      name = "ubuntu-work-browser";
      runtimeInputs = [pkgs.coreutils pkgs.libvirt pkgs.openssh pkgs.xpra];
      text = ''
        VIRSH=virsh
        if [[ "$($VIRSH --connect qemu:///system domstate ubuntu-work 2>/dev/null || true)" != "running" ]]; then
          $VIRSH --connect qemu:///system start ubuntu-work
        fi

        ssh -o BatchMode=yes erik@${address} \
          /home/erik/.nix-profile/bin/xpra _audio_query >/dev/null

        XPRA_SOCKET_TIMEOUT=30 \
          XPRA_SSH_AGENT_AUTH=0 \
          exec xpra seamless ssh://erik@${address}/ \
          --ssh=paramiko:agent=no \
          --remote-xpra=/home/erik/.nix-profile/bin/xpra \
          --start-child=/home/erik/.nix-profile/bin/work-browser-xpra \
          --exit-with-children=yes \
          --exit-with-client=yes \
        --resize-display=off:6640x1920 \
          --desktop-scaling=no \
          --clipboard=yes \
          --clipboard-direction=both \
          --keyboard-layout=qwerty-fr \
          --keyboard-variant=qwerty-fr \
          --xvfb=/home/erik/.nix-profile/bin/work-Xvfb \
          --speaker=on \
          --speaker-codec=opus \
          --microphone=on \
          --microphone-codec=opus \
          --pulseaudio-command=/home/erik/.nix-profile/bin/work-pulseaudio \
          --printing=no \
          --webcam=no \
          --splash=no
      '';
    };
    browserDesktop = pkgs.makeDesktopItem {
      name = "ubuntu-work-browser";
      desktopName = "Work Browser";
      exec = "${browser}/bin/ubuntu-work-browser";
      icon = "brave-browser";
      categories = ["Network" "WebBrowser"];
    };
  in {
    environment.etc."libvirt/qemu/ubuntu-work.xml" = {
      source = ./ubuntu-work-domain.xml;
      mode = "0600";
    };
    environment.systemPackages = [viewer browser browserDesktop];
    programs.ssh.extraConfig = ''
      Host ubuntu-work
        HostName 192.168.122.74
        User erik
        Port 22
        ForwardAgent no
    '';
    systemd.tmpfiles.rules = [
      "z /var/lib/libvirt/images/nstech-tools.iso 0600 root root - -"
    ];

    # Define persistent state without interrupting a running work VM.
    systemd.services.ubuntu-work-vm = {
      description = "Define Ubuntu work VM";
      wantedBy = ["multi-user.target"];
      after = ["libvirtd.service"];
      requires = ["libvirtd.service"];
      unitConfig.ConditionPathExists = "/var/lib/libvirt/images/ubuntu-work.qcow2";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        VIRSH="${pkgs.libvirt}/bin/virsh"
        DHCP_HOST="<host mac='${mac}' name='ubuntu-work' ip='${address}'/>"
        if ! $VIRSH net-update default modify ip-dhcp-host "$DHCP_HOST" --live --config 2>/dev/null; then
          $VIRSH net-update default add-last ip-dhcp-host "$DHCP_HOST" --live --config
        fi
        $VIRSH define /etc/libvirt/qemu/ubuntu-work.xml
        $VIRSH autostart --disable ubuntu-work
      '';
    };
  };
}
