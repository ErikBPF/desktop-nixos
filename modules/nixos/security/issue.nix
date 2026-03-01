{...}: {
  # Add a warning banner for unauthorized users [BANN-7126]
  environment.etc."issue".text = ''
    ***************************************************************************
    *                               WARNING                                   *
    * This system is restricted to authorized users only. All activities on   *
    * this system are logged. Unauthorized access will be fully investigated  *
    * and reported to the appropriate law enforcement agencies.               *
    ***************************************************************************
  '';
}
