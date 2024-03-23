#!/usr/bin/env sh

hyprctl dispatch workspace 1
hyprctl dispatch movecusortocorner 2

# section 1 - clear
notify-send "This is a test notification!" &
~/Dots/config/rofi/bin/powermenu.nu &
sleep 0.5
grim ~/Dots/screenshots/1.png
pkill rofi
sleep 5

# section 2 - tiled
kitty nvim +19 ~/Dots/config/nvim/lua/plugins/misc.lua &
sleep 1
kitty lf &
sleep 0.5
hyprctl dispatch resizeactive 80 0
hyprctl dispatch exec kitty &
sleep 0.5
hyprctl dispatch resizeactive 0 -210
sleep 4
hyprctl dispatch movefocus r
sleep 2
grim ~/Dots/screenshots/2.png

# section 3 - dash
hyprctl dispatch workspace 2
hyprctl dispatch workspace special:dash
sleep 1
grim ~/Dots/screenshots/3.png

# section 4 - lockscreen
loginctl lock-session &
sleep 3
grim ~/Dots/screenshots/4.png
