#!/usr/bin/env nu

(rofi \
	-show drun \
	-modi run,drun \
    -no-lazy-grab \
	-scroll-method 0 \
	-drun-match-fields all \
	-drun-display-format "{name}" \
	-no-drun-show-actions \
	-theme /home/mrb/.config/rofi/default.rasi)
