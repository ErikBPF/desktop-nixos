{
  config,
  lib,
  ...
}: {
  options.modules.graphics = {
    enable = lib.mkEnableOption "graphics drivers";
    
    driver = lib.mkOption {
      type = lib.types.enum ["intel" "nvidia" "none"];
      default = "none";
      description = "Graphics driver to use";
    };
  };

  config = lib.mkIf config.modules.graphics.enable {
    imports = [
      (lib.mkIf (config.modules.graphics.driver == "intel") ./intel.nix)
      (lib.mkIf (config.modules.graphics.driver == "nvidia") ./nvidia.nix)
    ];
  };
}
