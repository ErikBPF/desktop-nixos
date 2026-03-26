{...}: {
  services.resolved = {
    enable = true;
    settings.Resolve.LLMNR = "no";
  };
}
