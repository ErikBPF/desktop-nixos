_: {
  flake.modules.home.mime = _: let
    browser = "brave-browser";
    pdf = "brave-browser";
    fileManager = "yazi";
  in {
    xdg.mimeApps = {
      enable = true;
      defaultApplications = {
        "text/html" = "${browser}.desktop";
        "x-scheme-handler/http" = "${browser}.desktop";
        "x-scheme-handler/https" = "${browser}.desktop";
        "x-scheme-handler/chrome" = "${browser}.desktop";
        "x-scheme-handler/about" = "${browser}.desktop";
        "x-scheme-handler/unknown" = "${browser}.desktop";
        "default-web-browser" = "${browser}.desktop";
        "application/xhtml+xml" = "${browser}.desktop";
        "application/x-extension-htm" = "${browser}.desktop";
        "application/x-extension-html" = "${browser}.desktop";
        "application/x-extension-shtml" = "${browser}.desktop";
        "application/x-extension-xhtml" = "${browser}.desktop";
        "application/x-extension-xht" = "${browser}.desktop";
        "application/pdf" = "${pdf}.desktop";
        "inode/directory" = "${fileManager}.desktop";
      };
    };
  };
}
