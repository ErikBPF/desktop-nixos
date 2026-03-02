{...}: {
  # Auditd & Accounting [ACCT-9622, ACCT-9628]
  security.auditd.enable = true;
  security.audit = {
    enable = true;
    backlogLimit = 8192;
    failureMode = "printk"; # 0=silent, 1=printk, 2=panic
  };

  # Enable sysstat for accounting [ACCT-9626]
  services.sysstat.enable = true;
}
