_: {
  flake.modules.home.kitty = _: {
    programs.kitty = {
      enable = true;
      settings = {
        font_size = 12;
        cursor_shape = "block";
        url_color = "#0087bd";
        url_style = " dotted";
        confirm_os_window_close = 0;
        background_opacity = 0.97;
      };
    };
  };
}
