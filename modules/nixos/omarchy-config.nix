{
  pkgs,
  inputs,
  ...
}: {
  imports = [
    inputs.omarchy-nix.nixosModules.default
  ];

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
