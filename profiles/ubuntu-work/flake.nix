{
  description = "Pinned Nix profile for the Ubuntu work machine";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = {nixpkgs, ...}: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {inherit system;};
    workBrowser = pkgs.writeShellScriptBin "work-browser" ''
      exec /usr/bin/brave-browser-stable "$@"
    '';
    workBrowserXpra = pkgs.writeShellScriptBin "work-browser-xpra" ''
      umask 077
      display_file="$XDG_RUNTIME_DIR/ubuntu-work-xpra-display"
      printf '%s\n' "$DISPLAY" > "$display_file"
      trap 'rm -f "$display_file"' EXIT
      GTK_THEME=Yaru:dark /usr/bin/brave-browser-stable \
        --user-data-dir=$HOME/.config/BraveSoftware/Brave-Browser-Xpra \
        --ozone-platform=x11 \
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
          xclip
        ]
        ++ [
          workBrowser
          workBrowserXpra
          workBrowserDesktop
          sshdPolicy
        ];
    };
  };
}
