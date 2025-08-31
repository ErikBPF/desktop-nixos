{
  pkgs,
  lib,
  inputs,
  ...
}: {
  imports = [
    inputs.omarchy-nix.nixosModules.default
  ];

  wayland.windowManager.hyprland.settings = {
    # Environment variables
    # https://wiki.hyprland.org/Configuring/Variables/#input
    input = lib.mkDefault {
      kb_layout = "us";
      kb_variant = "qwerty-fr";
      # kb_model =
      kb_options = compose:caps;
      # kb_rules =
      numlock_by_default = true;

      follow_mouse = 1;
      mouse_refocus = 1;
      float_switch_override_focus = 1;
      scroll_factor = 0.5;

      sensitivity = 0; # -1.0 - 1.0, 0 means no modification.

      touchpad = {
        natural_scroll = false;
      };
    };
  };

  omarchy = {
    full_name = "Erik Bogado";
    email_address = "erikbogado@gmail.com";
    theme = "tokyo-night";
    exclude_packages = with pkgs; [
    ];
    
    quick_app_bindings = [
      "SUPER, A, exec, $webapp=https://claude.ai"
      "SUPER, C, exec, $webapp=https://app.hey.com/calendar/weeks/"
      "SUPER, E, exec, $webapp=https://app.hey.com"
      "SUPER, Y, exec, $webapp=https://youtube.com/"
      "SUPER SHIFT, G, exec, $webapp=https://web.whatsapp.com/"

      "SUPER, B, exec, $browser"
      "SUPER, M, exec, $music"
      "SUPER, N, exec, $terminal -e nvim"
      "SUPER, T, exec, $terminal -e btop"
      "SUPER, D, exec, $terminal -e lazydocker"
      "SUPER, G, exec, $messenger"
      "SUPER, O, exec, obsidian -disable-gpu"
      "SUPER, slash, exec, $passwordManager"

      "SUPER, T, exec, $termina  "
      "SUPER, W, killactive, "
      "CTRL SHIFT, L, exec, hyprlock "
      "SUPER, P, exec, pkill wlogout || wlogout --protocol layer-shell "
      "SUPER, E, exec, $fileManager "
      "SUPER, V, togglefloating, "
      "SUPER, D, exec, pkill wofi || wofi "
      "SUPER SHIFT, F, pseudo, "
      "SUPER, F, fullscreen, "
      "SUPER, M, fullscreen, 1 "
      "CTRL SHIFT, J, togglesplit, "
      "SUPER SHIFT, S, exec, grim -g '$(slurp)' - | swappy -f - "
    ];
  };
}
