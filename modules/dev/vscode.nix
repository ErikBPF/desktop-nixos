_: {
  flake.modules.home.vscode = {pkgs, ...}: {
    programs.vscode = {
      enable = true;
      package = (pkgs.vscode.override {isInsiders = true;}).overrideAttrs (oldAttrs: rec {
        src = builtins.fetchTarball {
          url = "https://update.code.visualstudio.com/latest/linux-x64/insider";
          sha256 = "1mngnfq1gw5ny77xz7sn4520xm43ddvycfnp52cngi7wxvzb68bz"; # vscode-insiders
        };
        version = "latest";
      });
      mutableExtensionsDir = true;
    };
  };
}
