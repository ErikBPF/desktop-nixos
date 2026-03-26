{...}: {
  flake.modules.nixos.audit = {...}: {
    security.auditd.enable = true;
    security.audit = {
      enable = false;
      backlogLimit = 8192;
      failureMode = "printk";
    };
    services.sysstat.enable = true;
  };
}
