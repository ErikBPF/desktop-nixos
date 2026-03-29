_: {
  flake.modules.home.packages-desktop = {pkgs, ...}: {
    home.packages = with pkgs; [
      # --- Security & Authentication (desktop) ---
      nordpass
      ente-auth
    ];
  };
}
