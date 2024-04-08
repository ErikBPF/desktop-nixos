#!/usr/bin/env nu

try {
    pkill -9 hyprpaper
    pkill -9 dunst
    pkill -9 keepassxc
    pkill -9 poweralertd
    # pkill -9 nextcloud
}

sh -c 'hyprpaper &'
sh -c 'dunst &'
sh -c 'keepassxc &'
sh -c 'poweralertd &'
# sh -c 'nextcloud &'
