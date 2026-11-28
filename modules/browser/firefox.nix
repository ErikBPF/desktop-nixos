_: let
  # AMO add-on id → download slug. Extension management lives in the
  # home-manager module so one file owns the profile, its prefs and its add-ons.
  extensions = {
    "addon@darkreader.org" = "darkreader";
    "uBlock0@raymondhill.net" = "ublock-origin";
    "{7be2ba16-0f1e-4d93-9571-6f00277c6177}" = "videospeed";
    "enhancerforyoutube@nicetoolbox.com" = "enhancer-for-youtube";
    "nordpassff@niceforyou.com" = "nordpass-password-manager";
  };
in {
  flake.modules.home.firefox = {
    config,
    lib,
    ...
  }: {
    programs.firefox = {
      enable = true;
      configPath = "${config.xdg.configHome}/mozilla/firefox";

      policies.ExtensionSettings =
        lib.mapAttrs (_: slug: {
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/${slug}/latest.xpi";
          installation_mode = "normal_installed";
        })
        extensions;

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
}
