_: {
  flake.modules.nixos.dev-nix-ld = {pkgs, ...}: {
    programs.nix-ld = {
      enable = true;
      libraries = with pkgs; [
        stdenv.cc.cc.lib
        zlib
        openssl
        curl
        glib
        nss
        nspr
        libxkbcommon
        libgcc
        icu
      ];
    };
  };
}
