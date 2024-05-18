{inputs, ...}: {
  imports = [
    inputs.nh.nixosModules.default
  ];

  # nh default flake
  environment.variables.FLAKE = "/home/erik/Dev/nixland";

  nh = {
    enable = true;
    # weekly cleanup
    clean = {
      enable = true;
      extraArgs = "--keep-since 7d";
    };
  };
}
