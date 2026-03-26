{config, ...}: {
  flake.modules.home.git = {...}: {
    programs.git = {
      enable = true;
      settings = {
        user = {
          name = config.fullName;
          email = config.email;
        };
        credential.helper = "store";
      };
    };
  };
}
