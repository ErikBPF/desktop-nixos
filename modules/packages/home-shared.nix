_: {
  flake.modules.home.packages-shared = {pkgs, ...}: {
    home.packages = with pkgs; [
      # --- Security & Authentication ---
      gnupg

      # --- System Monitoring & Debugging ---
      iotop
      iftop
      strace
      ltrace
      sysstat
      ethtool

      # --- Command-line Utilities ---
      bat
      ripgrep-all
      jq
      yq-go
      tree
      which
      cowsay

      # --- GNU Utilities ---
      gnused
      gnutar

      # --- Networking Tools ---
      mtr
      iperf3
      dnsutils
      ldns
      aria2
      socat
      nmap
      ipcalc

      # --- Archive Utilities ---
      xz
    ];
  };
}
