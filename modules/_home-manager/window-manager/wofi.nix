{
  config,
  pkgs,
  ...
}: {
  home.file = {
    ".config/wofi/style.css" = {
      text = ''
        * {
            font-family: 'JetBrainsMono Nerd Font', monospace;
            font-size: 18px;
        }

        window {
            margin: 0px;
            border: #${config.colorScheme.palette.base01};
            background-color: #${config.colorScheme.palette.base01};
            border-radius: 2px;
        }

        #input {
            padding: 4px;
            margin: 4px;
            padding-left: 20px;
            border: none;
            color: #${config.colorScheme.palette.base05};
            font-weight: bold;
            background-color: #${config.colorScheme.palette.base01};
            outline: none;
            border-radius: 10px;
            margin: 10px;
            margin-bottom: 2px;
        }

        #input:focus {
            border: 0px solid #${config.colorScheme.palette.base01};;
            margin-bottom: 0px;
        }

        #inner-box {
            margin: 4px;
            border: 10px solid #${config.colorScheme.palette.base01};;
            color: #${config.colorScheme.palette.base05};
            font-weight: bold;
            background-color: #${config.colorScheme.palette.base01};
            border-radius: 10px;
        }

        #outer-box {
            margin: 0px;
            border: none;
            border-radius: 10px;
            background-color: #${config.colorScheme.palette.base01};
        }

        #scroll {
            margin-top: 5px;
            border: none;
            border-radius: 10px;
            margin-bottom: 5px;
            /* background: rgb(255,255,255); */
        }

        #img:selected {
            background-color: #${config.colorScheme.palette.base03};
            border-radius: 10px;
        }

        #text:selected {
            color: #${config.colorScheme.palette.base0E};
            margin: 0px 0px;
            border: none;
            border-radius: 10px;
            background-color: #${config.colorScheme.palette.base03};
        }

        #entry {
            margin: 0px 0px;
            border: none;
            border-radius: 10px;
            background-color: transparent;
        }

        #entry:selected {
            margin: 0px 0px;
            border: none;
            border-radius: 10px;
            background-color: #${config.colorScheme.palette.base03};
        }

        #entry image {
            -gtk-icon-transform: scale(0.7);
        }
      '';
    };
  };

  programs.wofi = {
    enable = true;
    settings = {
      width = 600;
      height = 350;
      location = "center";
      show = "drun";
      prompt = "Search...";
      filter_rate = 100;
      allow_markup = true;
      no_actions = true;
      halign = "fill";
      orientation = "vertical";
      content_halign = "fill";
      insensitive = true;
      allow_images = true;
      image_size = 40;
      gtk_dark = true;
    };
  };
}
# base00: "#1A1B26"
# base01: "#16161E"
# base02: "#2F3549"
# base03: "#444B6A"
# base04: "#787C99"
# base05: "#A9B1D6"
# base06: "#CBCCD1"
# base07: "#D5D6DB"
# base08: "#C0CAF5"
# base09: "#A9B1D6"
# base0A: "#0DB9D7"
# base0B: "#9ECE6A"
# base0C: "#B4F9F8"
# base0D: "#2AC3DE"
# base0E: "#BB9AF7"
# base0F: "#F7768E"

