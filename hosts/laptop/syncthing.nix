{
  pkgs,
  inputs,
  secrets,
  ...
}: {
  services.syncthing = {
    enable = true;
    guiAddress = "127.0.0.1:8384";
    openDefaultPorts = true;
    relay = {
      enable = true;
    };
    configDir = "/home/erik/.config/syncthing";
    dataDir = "/home/erik/.config/syncthing";
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
          path = "/home/erik/Downloads/";
          devices = [
            "Moon"
            "workstation"
          ];
        };
        "ykxhp-khmz2" = {
          label = "Documents";
          path = "/home/erik/Documents/";
          devices = [
            "Moon"
            "workstation"
          ];
        };
        "xbwsp-zwvsr" = {
          label = "kube";
          path = "/home/erik/.kube/";
          devices = [
            "Moon"
            "workstation"
          ];
        };
      };
    };
  };
}
