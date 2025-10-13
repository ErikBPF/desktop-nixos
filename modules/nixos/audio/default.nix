{
  config,
  lib,
  ...
}: {
  options.modules.audio.enable = lib.mkEnableOption "audio support (PipeWire)";

  config = lib.mkIf config.modules.audio.enable {
    imports = [
      ./pipewire.nix
    ];
  };
}
