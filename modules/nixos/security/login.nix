{...}: {
  # Set password aging in login.defs [AUTH-9286]
  environment.etc."login.defs".text = ''
    PASS_MAX_DAYS   90
    PASS_MIN_DAYS   1
    PASS_WARN_AGE   7
  '';
}
