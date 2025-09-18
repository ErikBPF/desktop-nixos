{
  inputs,
  config,
  ...
}: {

  sops = {
    secrets = {
      "syncthing/moon_id"  = {};
      "syncthing/archlinux_id" = {};
    };
  };

    home.file."Downloads/test".text = ''
    ${builtins.readFile config.sops.secrets."syncthing/moon_id".path}
    '';

  # services.syncthing = {
  #   overrideDevices = true;
  #   overrideFolders = true;
  #   tray = true;
  #   settings = {
  #     devices = {
  #       "Moon" = {
  #         id = builtins.readFile config.sops.secrets."syncthing/moon_id".path;
  #       };
  #       "archlinux" = {
  #         id = builtins.readFile config.sops.secrets."syncthing/archlinux_id".path;
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
  #     };
  #   };
  # };
}