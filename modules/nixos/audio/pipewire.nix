{
  config,
  lib,
  ...
}: {
  config = lib.mkIf config.modules.desktop.enable {
    # Disable PulseAudio in favor of PipeWire
    services.pulseaudio.enable = false;

    # Enable PipeWire for audio
    services.pipewire = {
      enable = true;
      alsa = {
        enable = true;
        support32Bit = true;
      };
      pulse.enable = true;
      jack.enable = true;
      wireplumber.enable = true;
    };

    # Enable rtkit for real-time audio priority
    security.rtkit.enable = true;

  programs = {
    noisetorch.enable = true;
  };
  };
}
