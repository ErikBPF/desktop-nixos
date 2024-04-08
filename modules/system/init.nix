{ config, lib, pkgs, ... }:

{
 system.activationScripts.shell.text = ''
    #!/bin/sh
    ${pkgs.starship}/bin/starship init nu > /home/erik/.cache/starship.nu  
    ${pkgs.zoxide}/bin/zoxide init nushell > /home/erik/.cache/zoxide.nu  
  '';

  system.activationScripts.dotfiles.text = ''
    #!/bin/sh
    mkdir -p /home/erik/.config
    cp -rf /persist/home/erik/desktop-nixos/config/* /home/erik/.config
  '';

  system.activationScripts.colors = {
    deps = [ "dotfiles" ];
    text =
      let
        renderTemplates = templates: (
          builtins.foldl' (x: y: x + y) "#!/bin/sh\n" (builtins.map
            (template:
              ''
                ${pkgs.mustache-go}/bin/mustache \
                /persist/home/erik/desktop-nixos/config/colors.yml \
                /persist/home/erik/desktop-nixos/config/${template}.mustache > \
                /home/erik/.config/${template} ; 
              ''
            )
            templates)
        );
      in
      renderTemplates [
        "kitty/colors.conf"
        "hypr/colors.conf"
        "hypr/scripts/swaylock.nu"
        "nvim/lua/colors/bases.lua"
        "rofi/colors.rasi"
        "dunst/dunstrc.d/colors.conf"
      ]
    ;
  };
}
