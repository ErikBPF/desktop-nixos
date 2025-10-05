{  ...
}: {
  # yazi file manager
  programs.yazi = {
    enable = true;

    enableFishIntegration = true;

    settings = {
      mgr = {
        layout = [ 1 3 4 ];
        sort_by = "alphabetical";
        sort_sensitive = true;
        sort_reverse = false;
        sort_dir_first = true;
        linemode = "none";
        show_hidden = true;
        show_symlink = true;
      };

      preview = {
        tab_size = 2;
        max_width = 600;
        max_height = 900;
      };
    };
  };
}
