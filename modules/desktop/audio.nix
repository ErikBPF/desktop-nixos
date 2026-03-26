{...}: {
  flake.modules.nixos.audio = {...}: {
    services.pulseaudio.enable = false;
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
    security.rtkit.enable = true;
    programs.noisetorch.enable = true;
  };
}
