{
  lib,
  self,
  ...
}: {
  options = {
    username = lib.mkOption {
      type = lib.types.singleLineStr;
      readOnly = true;
      default = "erik";
    };
    fullName = lib.mkOption {
      type = lib.types.singleLineStr;
      readOnly = true;
      default = "Erik Bogado";
    };
    email = lib.mkOption {
      type = lib.types.singleLineStr;
      readOnly = true;
      default = "erikbogado@gmail.com";
    };
    configPath = lib.mkOption {
      type = lib.types.path;
      readOnly = true;
      default = self + "/config";
      description = "Path to non-nix assets (wallpapers, keyboard, quickshell QML)";
    };
  };
}
