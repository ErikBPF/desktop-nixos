{
  config,
  inputs,
  ...
}: let
  inherit (config.colorScheme) palette;
in {
  # Stylix — single-source theming generated from the nix-colors base16 scheme
  # (modules/theme.nix is still the SSOT: change the scheme there, everything
  # follows). autoEnable = false makes this opt-in per target, so the modules
  # that already derive cleanly from `colorScheme.palette` by hand
  # (hyprland/rofi/mako/hyprlock/quickshell) and the per-app named themes
  # (yazi flavor, ghostty, btop, vscode) stay exactly as they are. Stylix only
  # takes over the sprawl it removes: GTK, Qt, cursor, fonts, console.
  flake.modules.nixos.stylix = {pkgs, ...}: {
    imports = [inputs.stylix.nixosModules.stylix];

    stylix = {
      enable = true;
      autoEnable = false;
      polarity = "dark";
      # Feed Stylix the same palette the hand-tuned modules read — no drift.
      base16Scheme = palette;
      image = config.configPath + "/themes/wallpapers/wallpaper.png";

      cursor = {
        package = pkgs.vimix-cursors;
        name = "Vimix-cursors";
        size = 24;
      };

      fonts = {
        monospace = {
          package = pkgs.nerd-fonts.jetbrains-mono;
          name = "JetBrainsMono Nerd Font";
        };
        sansSerif = {
          package = pkgs.noto-fonts;
          name = "Noto Sans";
        };
        serif = {
          package = pkgs.noto-fonts;
          name = "Noto Serif";
        };
        emoji = {
          package = pkgs.noto-fonts-color-emoji;
          name = "Noto Color Emoji";
        };
      };

      # NixOS-level targets (system console + system Qt platform theme).
      targets.console.enable = true;
      targets.qt.enable = true;
    };
  };

  # HM-level opt-in targets (desktop only). GTK + Qt are the duplication Stylix
  # replaces — it generates both themes from the base16 scheme above.
  flake.modules.home.stylix = _: {
    stylix.targets = {
      gtk.enable = true;
      qt.enable = true;
    };
  };
}
