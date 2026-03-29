_: {
  flake.modules.nixos.login = _: {
    security.loginDefs.settings = {
      PASS_MAX_DAYS = 90;
      PASS_MIN_DAYS = 1;
      PASS_WARN_AGE = 7;
    };
  };
}
