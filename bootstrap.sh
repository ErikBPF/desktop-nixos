#!/usr/bin/env sh

nix shell -I ~/Dots nixpkgs#nushell nixpkgs#libressl --command nu -n -c "source ~desktop-nixos/Dots/config/nushell/alias.nu; rebuild boot"
