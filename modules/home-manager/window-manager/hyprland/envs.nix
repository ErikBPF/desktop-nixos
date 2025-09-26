{
  config,
  lib,
  pkgs,
  osConfig ? {},
  ...
}: let
  hasNvidiaDrivers = builtins.elem "nvidia" osConfig.services.xserver.videoDrivers;
  nvidiaEnv = [
    "NVD_BACKEND,direct"
    "LIBVA_DRIVER_NAME,nvidia"
    "__GLX_VENDOR_LIBRARY_NAME,nvidia"
    "__NV_PRIME_RENDER_OFFLOAD,1"
    "__VK_LAYER_NV_optimus,NVIDIA_only"
  ];
in {
  wayland.windowManager.hyprland.settings = {
    # Environment variables
    env =
      (lib.optionals hasNvidiaDrivers nvidiaEnv)
      ++ [
        "GDK_SCALE,1"

        # Cursor size
        "XCURSOR_SIZE,24"
        "HYPRCURSOR_SIZE,24"

        # Cursor theme
        "XCURSOR_THEME,Vimix-cursors"
        "HYPRCURSOR_THEME,Vimix-cursors"

        # Force all apps to use Wayland
        "GDK_BACKEND,wayland"
        "QT_QPA_PLATFORM,wayland"
        "QT_QPA_PLATFORMTHEME,qt6ct"
        "QT_STYLE_OVERRIDE,kvantum"
        "SDL_VIDEODRIVER,wayland"
        "MOZ_ENABLE_WAYLAND,1"
        "ELECTRON_OZONE_PLATFORM_HINT,wayland"
        "OZONE_PLATFORM,wayland"
        "NIXOS_OZONE_WL,1"

        # Make Chromium use XCompose and all Wayland
        "CHROMIUM_FLAGS,\"--enable-features=UseOzonePlatform --enable-features=WebRTCPipeWireCapturer --ozone-platform=wayland  --gtk-version=4\""

        # --enable-features=VaapiVideoDecoder,VaapiIgnoreDriverChecks,Vulkan,DefaultANGLEVulkan,VulkanFromANGLE --use-angle=vulkan --use-cmd-decoder=passthrough
        
        # Make .desktop files available for wofi
        "XDG_DATA_DIRS,$XDG_DATA_DIRS:$HOME/.nix-profile/share:/nix/var/nix/profiles/default/share"

        # Use XCompose file
        "XCOMPOSEFILE,~/.XCompose"
        "EDITOR,nvim"

        # GTK theme
        "GTK_THEME,Adwaita:dark"
        # Podman compatibility. Probably need to add cfg.env?
        # "DOCKER_HOST,unix://$XDG_RUNTIME_DIR/podman/podman.sock"
      ];

    xwayland = {
      force_zero_scaling = true;
    };

    # Don't show update on first launch
    ecosystem = {
      no_update_news = true;
    };
  };
}
