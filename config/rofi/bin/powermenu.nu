#!/usr/bin/env nu
def rofi_command [opts: string] { echo $opts | rofi -theme /home/mrb/.config/rofi/five.rasi -dmenu -selected-row 2 }

let i_shutdown = "󰐥"
let i_reboot = "󰜉"
let i_lock = "󰍁"
let i_suspend = "󰤄"
let i_logout = "󰍃"

let opts = $"($i_shutdown)\n($i_reboot)\n($i_lock)\n($i_suspend)\n($i_logout)"
let choice = (rofi_command $opts)

if ($i_shutdown in $choice) { systemctl poweroff }
if ($i_reboot in $choice) { systemctl reboot }
if ($i_lock in $choice) { loginctl lock-session }
if ($i_suspend in $choice) { systemctl suspend }
if ($i_logout in $choice) { hyprctl dispatch exit }
