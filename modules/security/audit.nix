_: {
  flake.modules.nixos.audit = {
    lib,
    pkgs,
    ...
  }: let
    # The upstream security.audit module emits -b/-f/-r into the rules file,
    # but the kernel returns EOPNOTSUPP for AUDIT_SET via netlink post-init
    # (these are already set via boot params: audit_backlog_limit=8192).
    # auditctl -R fails hard on the first EOPNOTSUPP, loading no rules at all.
    # Fix: generate a rules-only file (no config flags) and override ExecStart.
    auditRules = pkgs.writeTextDir "audit.rules" ''
      -D
      -a never,exclude -F msgtype=BPF
      -a never,exclude -F msgtype=NETFILTER_CFG
      -a never,exclude -F msgtype=ANOM_PROMISCUOUS
      -w /etc/pam.d/ -p wa -k auth_config
      -w /etc/shadow -p wa -k shadow_changes
      -w /etc/passwd -p wa -k passwd_changes
      -w /etc/group -p wa -k group_changes
      -w /etc/sudoers -p wa -k sudoers_changes
      -w /var/log/sudo.log -p wa -k sudo_log
    '';
  in {
    security.auditd.enable = true;
    security.auditd.settings = {
      max_log_file = 256;
      max_log_file_action = "ROTATE";
      num_logs = 8;
    };

    security.audit = {
      enable = true;
      backlogLimit = 8192; # sets audit_backlog_limit= boot param only; netlink set blocked post-init
      failureMode = "silent";
      rules = []; # managed via auditRules above to avoid -b/-f/-r in the loaded file
    };

    # Override ExecStart to load our rules-only file instead of the upstream
    # generated one that includes -b/-f/-r (EOPNOTSUPP on kernel 6.18+).
    systemd.services.audit-rules-nixos.serviceConfig.ExecStart =
      lib.mkForce "${pkgs.audit}/bin/auditctl -R ${auditRules}/audit.rules";

    services.sysstat.enable = true;
  };
}
