{
  ...
}:
let
  browser = "brave";
  pdf = "brave";
  fileManager = "yazi";
in
{
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

      # PDF MIME type
      "application/pdf" = "${pdf}.desktop";

      # File manager
      "inode/directory" = "${fileManager}.desktop";
    };
  };
}
