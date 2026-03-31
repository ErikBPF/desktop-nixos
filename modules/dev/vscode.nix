_: {
  flake.modules.home.vscode = {pkgs, ...}: {
    programs.vscode = {
      enable = true;
      package = (pkgs.vscode.override {isInsiders = true;}).overrideAttrs (oldAttrs: rec {
        src = builtins.fetchTarball {
          url = "https://update.code.visualstudio.com/latest/linux-x64/insider";
          sha256 = "0x4fxl9ba8bvflkkwwqnmpg7n2lkqm8xh35bfjv7wxql8imly6hj"; # vscode-insiders
        };
        version = "latest";
      });
      mutableExtensionsDir = true;
    };
  };
}
