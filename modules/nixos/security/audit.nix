{...}: {
  # Auditd & Accounting [ACCT-9622, ACCT-9628]
  security.auditd.enable = true;
  security.audit = {
    enable = true;
    rules = [
      "-a exit,always -F arch=b64 -S execve"
    ];
  };

  # Enable sysstat for accounting [ACCT-9626]
  services.sysstat.enable = true;
}
