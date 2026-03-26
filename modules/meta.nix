{lib, ...}: {
  options.username = lib.mkOption {
    type = lib.types.singleLineStr;
    readOnly = true;
    default = "erik";
  };
  options.fullName = lib.mkOption {
    type = lib.types.singleLineStr;
    readOnly = true;
    default = "Erik Bogado";
  };
  options.email = lib.mkOption {
    type = lib.types.singleLineStr;
    readOnly = true;
    default = "erikbogado@gmail.com";
  };
  options.configPath = lib.mkOption {
    type = lib.types.path;
    readOnly = true;
    default = ../../config;
    description = "Path to non-nix assets (wallpapers, keyboard, quickshell QML)";
  };
}
