{
  config,
  lib,
  ...
}: {
  options.modules.dev.enable = lib.mkEnableOption "development tools and environments";

  config = lib.mkIf config.modules.dev.enable {
    imports = [
      ./paths.nix
      ./dotnet.nix
      ./go.nix
      ./python.nix
      ./java.nix
      ./javascript.nix
    ];
  };
}
