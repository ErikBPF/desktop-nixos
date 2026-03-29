{config, ...}: {
  flake.modules.nixos.xserver = _: {
    services.xserver.xkb = {
      layout = "qwerty-fr";
      variant = "qwerty-fr";
      extraLayouts = {
        qwerty-fr = {
          description = "QWERTY with French symbols and diacritics";
          languages = ["eng"];
          symbolsFile = config.configPath + "/keyboard/us_qwerty-fr";
        };
      };
    };
  };
}
