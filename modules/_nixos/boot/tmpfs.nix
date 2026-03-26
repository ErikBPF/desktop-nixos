{...}: {
  # Secure /tmp [FILE-6310]
  boot.tmp.useTmpfs = true;
  boot.tmp.cleanOnBoot = true;
}