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

  services.syncthing = {
    overrideDevices = true;
    overrideFolders = true;
    configDir = "/home/erik/.config/syncthing";
    settings = {
      devices = {
        "Moon" = {
          id = builtins.readFile config.sops.secrets."syncthing/moon_id".path;
        };
        "archlinux" = {
          id = builtins.readFile config.sops.secrets."syncthing/archlinux_id".path;
        };
      };

      folders = {
        "ndykv-cjhly" = {
          label = "Downloads";
          path = "/home/erik/Downloads/";
          devices = [
            "Moon"
            "archlinux"
          ];
        };
      };
    };
  };
}