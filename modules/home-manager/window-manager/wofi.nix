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
            background-color: #${config.colorScheme.palette.base05};
            border-radius: 15px;
        }

        #input {
            padding: 4px;
            margin: 4px;
            padding-left: 20px;
            border: none;
            color: #${config.colorScheme.palette.base05};
            font-weight: bold;
            background-color: #${config.colorScheme.palette.base00};
            outline: none;
            border-radius: 15px;
            margin: 10px;
            margin-bottom: 2px;
        }

        #input:focus {
            border: 0px solid #1e1e2e;
            margin-bottom: 0px;
        }

        #inner-box {
            margin: 4px;
            border: 10px solid #1e1e2e;
            color: #${config.colorScheme.palette.base05};
            font-weight: bold;
            background-color: #${config.colorScheme.palette.base00};
            border-radius: 15px;
        }

        #outer-box {
            margin: 0px;
            border: none;
            border-radius: 15px;
            background-color: #${config.colorScheme.palette.base00};
        }

        #scroll {
            margin-top: 5px;
            border: none;
            border-radius: 15px;
            margin-bottom: 5px;
            /* background: rgb(255,255,255); */
        }

        #img:selected {
            background-color: #${config.colorScheme.palette.base01};
            border-radius: 15px;
        }

        #text:selected {
            color: #${config.colorScheme.palette.base01};
            margin: 0px 0px;
            border: none;
            border-radius: 15px;
            background-color: #${config.colorScheme.palette.base01};
        }

        #entry {
            margin: 0px 0px;
            border: none;
            border-radius: 15px;
            background-color: transparent;
        }

        #entry:selected {
            margin: 0px 0px;
            border: none;
            border-radius: 15px;
            background-color: #${config.colorScheme.palette.base04};
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
