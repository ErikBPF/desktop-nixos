_: {
  flake.modules.home.gpg = {pkgs, ...}: {
    programs = {
      command-not-found.enable = false;
      gpg.enable = true;
    };
    services.gpg-agent = {
      enable = true;
      enableSshSupport = true;
      enableExtraSocket = true;
      sshKeys = ["D528D50F4E9F031AACB1F7A9833E49C848D6C90"];
      pinentry.package = pkgs.pinentry-gnome3;
    };
  };
}
