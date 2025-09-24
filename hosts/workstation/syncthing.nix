{
  pkgs,
  secrets,
  inputs,
  config,
  ...
}: {
  # services.syncthing = {
  #   enable = false;
  #   guiAddress = "127.0.0.1:8384";
  #   openDefaultPorts = true;
  #   relay = {
  #     enable = true;
  #   };
  #   configDir = "/home/erik/.config/syncthing";
  #   dataDir = "/home/erik/.config/syncthing";
  #   overrideDevices = true;
  #   overrideFolders = true;
  #   user = "erik";
  #   settings = {
  #     devices = {
  #       "Moon" = {
  #         id = ''${secrets.syncthing.moon_id}'';
  #       };
  #       "archlinux" = {
  #         id = ''${secrets.syncthing.archlinux_id}'';
  #       };
  #     };

  #     folders = {
  #       "ndykv-cjhly" = {
  #         label = "Downloads";
  #         path = "/home/erik/Downloads/";
  #         devices = [
  #           "Moon"
  #           "archlinux"
  #         ];
  #       };
  #       "ykxhp-khmz2" = {
  #         label = "Documents";
  #         path = "/home/erik/Documents/";
  #         devices = [
  #           "Moon"
  #           "archlinux"
  #         ];
  #       };
  #       "xbwsp-zwvsr" = {
  #         label = "kube";
  #         path = "/home/erik/.kube/";
  #         devices = [
  #           "Moon"
  #           "archlinux"
  #         ];
  #       };
  #     };
  #   };
  # };
}
