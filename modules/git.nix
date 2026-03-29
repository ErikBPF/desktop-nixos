{config, ...}: {
  flake.modules.home.git = _: {
    programs.git = {
      enable = true;
      settings = {
        user = {
          name = config.fullName;
          inherit (config) email;
        };
        credential.helper = "store";
      };
    };
  };
}
