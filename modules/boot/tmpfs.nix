_: {
  flake.modules.nixos.boot-tmpfs = _: {
    boot.tmp.useTmpfs = true;
    boot.tmp.cleanOnBoot = true;
  };
}
