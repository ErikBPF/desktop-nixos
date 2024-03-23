{ config, lib, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    nushell
    starship
    zoxide
    macchina
    bottom
    lf
    zellij
    fzf
    fd
    ripgrep
    ctpv
    eza
    viu
    bat
    file
    rclone
    carapace
    tty-clock

    cargo
    gcc
    nixpkgs-fmt
    #nixd
    lua-language-server
    zls
    zig
    python3
    jq
    libressl
  ];

  programs = {
    git.enable = true;
    neovim.enable = true;
    neovim.defaultEditor = true;
  };
}
