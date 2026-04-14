_: {
  # Home-manager module: profile settings
  flake.modules.home.firefox = {
    pkgs,
    lib,
    ...
  }: {
    programs.firefox = {
      enable = true;

      profiles.default = {
        isDefault = true;

        settings = {
          # Hardware video acceleration (VA-API)
          "media.ffmpeg.vaapi.enabled" = true;
          "media.hardware-video-decoding.enabled" = true;
          "media.hardware-video-decoding.force-enabled" = true;

          # WebRTC hardware encode via VA-API
          "media.navigator.mediadatadecoder_vpx_enabled" = true;
          "media.webrtc.hw.h264.enabled" = true;

          # Wayland native
          "widget.use-xdg-desktop-portal.file-picker" = 1;
          "widget.use-xdg-desktop-portal.mime-handler" = 1;

          # Performance
          "gfx.webrender.all" = true;
          "layers.acceleration.force-enabled" = true;
        };
      };
    };
  };

  # NixOS module: policies (system-wide, manages extensions)
  flake.modules.nixos.firefox-policies = _: {
    programs.firefox = {
      enable = true;
      policies = {
        ExtensionSettings = {
          # Dark Reader
          "addon@darkreader.org" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/darkreader/latest.xpi";
            installation_mode = "normal_installed";
          };
          # uBlock Origin
          "uBlock0@raymondhill.net" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
            installation_mode = "normal_installed";
          };
          # Video Speed Controller
          "{7be2ba16-0f1e-4d93-9571-6f00277c6177}" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/videospeed/latest.xpi";
            installation_mode = "normal_installed";
          };
          # Enhancer for YouTube
          "enhancerforyoutube@nicetoolbox.com" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/enhancer-for-youtube/latest.xpi";
            installation_mode = "normal_installed";
          };
          # NordPass
          "nordpassff@niceforyou.com" = {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/nordpass-password-manager/latest.xpi";
            installation_mode = "normal_installed";
          };
        };
      };
    };
  };
}
