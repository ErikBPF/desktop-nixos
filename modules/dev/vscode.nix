_: {
  flake.modules.home.vscode = {pkgs, ...}: {
    programs.vscode = {
      enable = true;
      package = pkgs.vscode;
      mutableExtensionsDir = true;
    };
  };
}
