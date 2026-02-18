{
  pkgs,
  inputs,
  secrets,
  config,
  ...
}: let
  homeDir = config.users.users.erik.home;
in {
  services.syncthing = {
    enable = false;
    guiAddress = "127.0.0.1:8384";
    openDefaultPorts = true;
    relay = {
      enable = true;
    };
    configDir = "${homeDir}/.config/syncthing";
    dataDir = "${homeDir}/.config/syncthing";
    overrideDevices = true;
    overrideFolders = true;
    user = "erik";
    settings = {
      devices = {
        "Moon" = {
          id = ''${secrets.syncthing.moon_id}'';
        };
        "archlinux" = {
          id = ''${secrets.syncthing.archlinux_id}'';
        };
      };

      folders = {
        "ndykv-cjhly" = {
          label = "Downloads";
          path = "${homeDir}/Downloads/";
          devices = [
            "Moon"
            "archlinux"
          ];
        };
        "ykxhp-khmz2" = {
          label = "Documents";
          path = "${homeDir}/Documents/";
          devices = [
            "Moon"
            "archlinux"
          ];
        };
        "xbwsp-zwvsr" = {
          label = "kube";
          path = "${homeDir}/.kube/";
          devices = [
            "Moon"
            "archlinux"
          ];
        };
      };
    };
  };
}
