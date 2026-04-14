_: {
  flake.modules.nixos.laptop-appimage = _: {
    programs.appimage = {
      enable = true;
      binfmt = true;
    };
  };
}
