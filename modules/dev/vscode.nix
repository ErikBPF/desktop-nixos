{...}: {
  flake.modules.home.vscode = {pkgs, ...}: {
    programs.vscode = {
      enable = true;
      package = (pkgs.vscode.override {isInsiders = true;}).overrideAttrs (oldAttrs: rec {
        src = builtins.fetchTarball {
          url = "https://update.code.visualstudio.com/latest/linux-x64/insider";
          sha256 = "0j7m5mnzhh2g53rhnn0lgih3xc5i5nm9zq1ibmmfxps6hzgyqnga";
        };
        version = "latest";
      });
      mutableExtensionsDir = true;
    };
  };
}
