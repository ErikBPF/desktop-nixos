{...}: {
  services = {
    # SSD trim
    fstrim = {
      enable = true;
      interval = "weekly";
      # udev.extraRules = ''

      # HDD
      # ACTION == "add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="1", \
      #   ATTR{queue/scheduler}="bfq"

      # SSD
      # ACTION=="add|change", KERNEL=="sd[a-z]*|mmcblk[0-9]*", ATTR{queue/rotational}=="0", \
      #   ATTR{queue/scheduler}="mq-deadline"

      # NVMe SSD
      # ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/rotational}=="0", \
      #   ATTR{queue/scheduler}="none"
      # '';
    };

    # SMART disk monitoring
    smartd = {
      enable = true;
      autodetect = true;
    };

    # Early OOM killer
    earlyoom = {
      enable = true;
      freeMemThreshold = 5;
      freeSwapThreshold = 10;
    };

    # Auto-tune system performance
    bpftune.enable = true;
  };

  # Enable BCC for bpftune
  programs.bcc.enable = true;
}
