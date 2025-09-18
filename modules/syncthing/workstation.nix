{
  inputs,
  ...
}: {

  sops = {
    age = {
      keyFile = "/home/erik/.config/sops/age/keys.txt";
      generateKey = true;
    };
    defaultSopsFormat = "yaml";
    defaultSopsFile = ../../secrets/secrets.yaml;
    secrets = {
      "syncthing/moon_id"  = {};
      "syncthing/archlinux_id" = {};
    };
  };

    # home.file."Downloads/test".text = ''${builtins.readFile config.sops.secrets."syncthing/moon_id".path}'';aq
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
    user= "erik";
    # settings = {
    #   devices = {
    #     "Moon" = {
    #       id = ''${builtins.readFile config.sops.secrets."syncthing/moon_id".path}'';
    #     };
    #     "archlinux" = {
    #       id = ''${builtins.readFile config.sops.secrets."syncthing/moon_id".path}'';
    #     };
    #   };

    #   folders = {
    #     "ndykv-cjhly" = {
    #       label = "Downloads";
    #       path = "/home/erik/Downloads/";
    #       devices = [
    #         "Moon"
    #         "archlinux"
    #       ];
    #     };
    #   };
    # };
  };
}