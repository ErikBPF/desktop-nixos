{lib, ...}: {
  imports = [
    ./intel.nix
    ./nvidia.nix
  ];

  options.modules.graphics = {
    enable = lib.mkEnableOption "graphics drivers";

    driver = lib.mkOption {
      type = lib.types.enum ["intel" "nvidia" "none"];
      default = "none";
      description = "Graphics driver to use";
    };
  };
}
