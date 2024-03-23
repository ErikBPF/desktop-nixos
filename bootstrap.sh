#!/usr/bin/env sh

nix shell -I ~/desktop-nixos nixpkgs#nushell nixpkgs#libressl --command nu -n -c "source ~/desktop-nixos/config/nushell/alias.nu; rebuild boot"
