{
  description = "Pinned Nix profile for the Ubuntu work machine";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = {nixpkgs, ...}: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {inherit system;};
    workBrowser = pkgs.writeShellScriptBin "work-browser" ''
      exec /usr/bin/brave-browser-stable "$@"
    '';
    workXvfb = pkgs.writeShellScriptBin "work-Xvfb" ''
      exec /usr/bin/Xvfb "$@"
    '';
    workPulseaudio = pkgs.writeShellScriptBin "work-pulseaudio" ''
      socket="/run/user/$UID/xpra/''${DISPLAY#:}/pulse/native"
      # Xpra 6.4 classifies Pulse devices using "input" in their names.
      exec ${pkgs.pulseaudio}/bin/pulseaudio --start -n \
        --daemonize=false --system=false --exit-idle-time=-1 \
        --load=module-suspend-on-idle \
        "--load=module-null-sink sink_name=Xpra-Microphone sink_properties=device.description=Xpra-Microphone" \
        "--load=module-null-sink sink_name=Xpra-Speaker sink_properties=device.description=Xpra-Speaker" \
        "--load=module-remap-source source_name=Xpra-Mic-Input source_properties=device.description=Xpra-Mic-Input master=Xpra-Microphone.monitor channels=1" \
        "--load=module-native-protocol-unix socket=$socket auth-cookie=\$PULSE_COOKIE auth-cookie-enabled=1" \
        --log-level=2 --log-target=stderr
    '';
    workBrowserXpra = pkgs.writeShellScriptBin "work-browser-xpra" ''
      PULSE_SINK=Xpra-Speaker \
        PULSE_SOURCE=Xpra-Mic-Input \
        GTK_THEME=Yaru:dark \
        exec /usr/bin/brave-browser-stable \
        --user-data-dir=$HOME/.config/BraveSoftware/Brave-Browser-Xpra \
        --ozone-platform=x11 \
        --window-size=1920,1080 \
        --force-dark-mode \
        --restore-last-session
    '';
    workBrowserDesktop = pkgs.makeDesktopItem {
      name = "work-browser";
      desktopName = "Work Browser";
      exec = "${workBrowser}/bin/work-browser %U";
      icon = "brave-browser";
      categories = ["Network" "WebBrowser"];
      startupNotify = true;
    };
    sshdPolicy = pkgs.writeTextDir "share/ubuntu-work/sshd_config" ''
      PasswordAuthentication no
      PubkeyAuthentication yes
      PermitRootLogin no
      X11Forwarding no
      AllowUsers erik
    '';
  in {
    packages.${system}.default = pkgs.buildEnv {
      name = "ubuntu-work-profile";
      paths = with pkgs;
        [
          openssh
          tmux
          git
          curl
          jq
          ripgrep
          rsync
          sqlite
          netcat-openbsd
          xpra
        ]
        ++ [
          workBrowser
          workXvfb
          workPulseaudio
          workBrowserXpra
          workBrowserDesktop
          sshdPolicy
        ];
    };
  };
}
