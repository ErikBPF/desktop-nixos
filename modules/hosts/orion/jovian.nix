{inputs, ...}: {
  flake.modules.nixos.orion-jovian = {
    lib,
    pkgs,
    ...
  }: {
    # --- Jovian Steam HTPC ---
    jovian.steam.enable = true;
    jovian.steam.autoStart = true;
    jovian.steam.user = "erik";
    jovian.steam.desktopSession = "hyprland";
    jovian.hardware.has.amd.gpu = true;

    # --- AMD GPU environment ---
    environment.variables.AMD_VULKAN_ICD = "RADV";

    # --- Remove -steamdeck flag from Steam ---
    # Jovian's overlay bakes -steamdeck into steam-wrapped via platformArgs in fhsenv.nix.
    # This makes Steam and all games identify the system as a Steam Deck → Deck resolutions.
    #
    # Fix: add an overlay (mkAfter → runs after Jovian's) that re-calls the nixpkgs
    # steam wrapper (pkgs/by-name/st/steam/package.nix) using Jovian's Jupiter
    # steam-unwrapped as the base, but with platformArgs = "" (omitting -steamdeck).
    nixpkgs.overlays = lib.mkAfter [
      (final: _prev: {
        steam =
          final.callPackage
          "${inputs.jovian}/pkgs/steam-jupiter/fhsenv.nix"
          {
            # Use the nixpkgs steam (not Jovian's already-wrapped result) as base.
            # We reconstruct that by calling package.nix directly with Jupiter unwrapped.
            steam =
              final.callPackage
              "${pkgs.path}/pkgs/by-name/st/steam/package.nix"
              {inherit (final) steam-unwrapped;};
            platformArgs = "";
          };
      })
    ];

    # --- Gamescope desktop connector fix + 4K output ---
    # Jovian's gamescope-session script hardcodes:
    #   --generate-drm-mode fixed -w 1280 -h 800 -O *,eDP-1
    # On a desktop HDMI TV (no eDP), this produces a blank screen.
    #
    # Fix: write a gamescope shim to /run/gamescope-desktop-shim/gamescope
    # and prepend that directory to PATH via the Jovian pre-start hook.
    # The shim strips Deck-specific flags and substitutes desktop values.
    #
    # Resolution strategy:
    #   -W/-H = output resolution sent to the TV (always 4K)
    #   -w/-h = default game render resolution (4K)
    # Steam Big Picture exposes a per-game resolution override (4K / 1440p / 1080p)
    # which changes -w/-h at launch time. --max-scale 2 handles upscaling when a game
    # renders at a lower resolution than the 4K output.
    environment.etc."jovian/gamescope-session/pre-start".text = ''
      export PATH=/run/gamescope-desktop-shim:''${PATH}
    '';

    # The shim is created at activation time. /run is tmpfs so it is
    # always fresh on each boot; activation ensures it matches the current system.
    system.activationScripts.gamescopeDesktopShim = {
      text = ''
                install -d -m 0755 /run/gamescope-desktop-shim
                cat > /run/gamescope-desktop-shim/gamescope << 'EOF'
        #!/bin/sh
        # Gamescope desktop shim for Orion (HDMI-A-1, no eDP panel).
        # Passes through only runtime args (-e, -R socket, -T stats),
        # replacing Steam-Deck-specific resolution/mode/output with desktop values.
        extra=""
        i=1
        while [ "$i" -le "$#" ]; do
          eval "arg=\''${$i}"
          case "$arg" in
            -e) extra="$extra -e" ;;
            -R) i=$((i+1)); eval "val=\''${$i}"; extra="$extra -R $val" ;;
            -T) i=$((i+1)); eval "val=\''${$i}"; extra="$extra -T $val" ;;
            -w|-h|-W|-H) i=$((i+1)) ;;
            --generate-drm-mode|--xwayland-count|--default-touch-mode|\
            --hide-cursor-delay|--max-scale|--fade-out-duration|\
            --cursor-scale-height|-O) i=$((i+1)) ;;
          esac
          i=$((i+1))
        done
        exec ${pkgs.gamescope}/bin/gamescope \
          --generate-drm-mode cvt \
          --xwayland-count 2 \
          -W 3840 -H 2160 \
          -w 3840 -h 2160 \
          --default-touch-mode 4 \
          --hide-cursor-delay 3000 \
          --max-scale 2 \
          --fade-out-duration 200 \
          --cursor-scale-height 2160 \
          -O HDMI-A-1 \
          $extra
        EOF
                chmod 0755 /run/gamescope-desktop-shim/gamescope
      '';
      deps = [];
    };

    # --- Sleep / idle inhibit ---
    # Orion is an always-on HTPC. Disable all OS-level sleep so Steam's
    # own steamos-manager handles any suspend/wake logic it needs.
    # HandlePowerKey=ignore is already set by Jovian (conflicts with powerbuttond).
    services.logind.settings.Login = {
      IdleAction = "ignore";
      HandleSuspendKey = "ignore";
      HandleHibernateKey = "ignore";
      HandleLidSwitch = "ignore";
      HandleLidSwitchExternalPower = "ignore";
    };
    # Disable systemd-sleep entirely on a desktop that never suspends
    systemd.targets.sleep.enable = false;
    systemd.targets.suspend.enable = false;
    systemd.targets.hibernate.enable = false;
    systemd.targets.hybrid-sleep.enable = false;

    # --- /scratch ownership ---
    # disko formats /scratch as ext4 but doesn't set permissions.
    # Declare ownership via tmpfiles so it survives nixos-rebuild.
    systemd.tmpfiles.rules = [
      "d /scratch 0755 erik users -"
    ];

    # --- Silent boot ---
    boot.kernelParams = lib.mkAfter [
      "quiet"
      "splash"
      "rd.systemd.show_status=false"
      "rd.udev.log_level=3"
      "udev.log_priority=3"
    ];
    boot.consoleLogLevel = 0;
  };
}
