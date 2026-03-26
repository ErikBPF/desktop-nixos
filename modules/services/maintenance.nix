{...}: {
  flake.modules.nixos.maintenance = {...}: {
    services = {
      fstrim = {
        enable = true;
        interval = "weekly";
      };
      smartd = {
        enable = true;
        autodetect = true;
      };
      earlyoom = {
        enable = true;
        freeMemThreshold = 5;
        freeSwapThreshold = 10;
      };
      bpftune.enable = true;
    };
    programs.bcc.enable = true;
  };
}
