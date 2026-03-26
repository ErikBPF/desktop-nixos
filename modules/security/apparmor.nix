{...}: {
  flake.modules.nixos.apparmor = {pkgs, ...}: {
    security.apparmor = {
      enable = true;
      packages = with pkgs; [
        apparmor-utils
        apparmor-profiles
      ];
    };
  };
}
