{...}: {
  flake.modules.nixos.boot-tmpfs = {...}: {
    boot.tmp.useTmpfs = true;
    boot.tmp.cleanOnBoot = true;
  };
}
