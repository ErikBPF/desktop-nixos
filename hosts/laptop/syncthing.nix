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
        "workstation" = {
          id = ''${secrets.syncthing.workstation_id}'';
        };
      };

      folders = {
        "ndykv-cjhly" = {
          label = "Downloads";
          path = "${homeDir}/Downloads/";
          devices = [
            "Moon"
            "workstation"
          ];
        };
        "ykxhp-khmz2" = {
          label = "Documents";
          path = "${homeDir}/Documents/";
          devices = [
            "Moon"
            "workstation"
          ];
        };
        "xbwsp-zwvsr" = {
          label = "kube";
          path = "${homeDir}/.kube/";
          devices = [
            "Moon"
            "workstation"
          ];
        };
      };
    };
  };
}
