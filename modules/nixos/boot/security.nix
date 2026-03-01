{...}: {
  # Lynis recommendations [NETW-3200]
  boot.blacklistedKernelModules = [
    # Obscure network protocols
    "dccp" "sctp" "rds" "tipc"
    # Disable USB storage if not needed [USB-1000]
    # "usb-storage" 
  ];

  # GRUB Boot Loader Password [BOOT-5122]
  # Prevent unauthorized users from altering boot configurations.
  # Uncomment and replace with output of: grub-mkpasswd-pbkdf2
  # boot.loader.grub.users = {
  #   root = {
  #     hashedPassword = "grub.pbkdf2.sha512.10000..."; 
  #   };
  # };
  
  # Kernel Sysctl Hardening [KRNL-6000]
  boot.kernel.sysctl = {
    "dev.tty.ldisc_autoload" = 0;
    "fs.protected_fifos" = 2;
    "fs.protected_regular" = 2;
    "fs.suid_dumpable" = 0;
    "kernel.kptr_restrict" = 2;
    "kernel.modules_disabled" = 1;
    "kernel.sysrq" = 0;
    "kernel.unprivileged_bpf_disabled" = 1;
    "net.core.bpf_jit_harden" = 2;
    "net.ipv4.conf.all.forwarding" = 0;
    "net.ipv4.conf.all.log_martians" = 1;
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.default.log_martians" = 1;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.default.accept_redirects" = 0;
  };
}