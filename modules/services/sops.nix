{
  self,
  config,
  ...
}: {
  flake.modules = {
    nixos.sops = _: {
      sops.age.keyFile = "/home/${config.username}/.config/sops/age/keys.txt";
    };

    home.sops = {config, ...}: {
      sops = {
        age = {
          keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
          generateKey = true;
        };
        defaultSopsFormat = "yaml";
        defaultSopsFile = self + "/secrets/sops/secrets.yaml";
        secrets = {
          password = {};
          id_ed25519 = {
            path = "${config.home.homeDirectory}/.ssh/id_ed25519";
            mode = "0400";
          };
          id_rsa = {
            path = "${config.home.homeDirectory}/.ssh/id_rsa";
            mode = "0400";
          };
        };
      };
    };
  };
}
