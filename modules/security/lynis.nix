_: {
  flake.modules.nixos.lynis = {pkgs, ...}: {
    environment.systemPackages = [pkgs.lynis];

    environment.etc."lynis/custom.prf".text = ''
      skip-test=FIRE-4590
      skip-test=BOOT-5122
      skip-test=PKGS-7398
      skip-test=TOOL-5002
      skip-test=FILE-7524
      skip-test=AUTH-9229
      skip-test=AUTH-9230
    '';
  };
}
