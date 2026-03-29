_: {
  flake.modules.nixos.audit = _: {
    security.auditd.enable = true;
    security.audit = {
      enable = true;
      backlogLimit = 8192;
      failureMode = "printk";
      rules = [
        "-w /etc/pam.d/ -p wa -k auth_config"
        "-w /etc/shadow -p wa -k shadow_changes"
        "-w /etc/passwd -p wa -k passwd_changes"
        "-w /etc/group -p wa -k group_changes"
        "-w /etc/sudoers -p wa -k sudoers_changes"
        "-w /var/log/sudo.log -p wa -k sudo_log"
        "-a always,exit -F arch=b64 -S execve -F euid=0 -F auid>=1000 -F auid!=4294967295 -k privilege_escalation"
        "-a always,exit -F arch=b64 -S mount -S umount2 -k mounts"
        "-a always,exit -F arch=b64 -S open -S openat -F exit=-EACCES -k access_denied"
        "-a always,exit -F arch=b64 -S open -S openat -F exit=-EPERM -k access_denied"
      ];
    };
    services.sysstat.enable = true;
  };
}
