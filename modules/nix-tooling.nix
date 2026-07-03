{inputs, ...}: {
  # Fleet-wide Nix ergonomics.
  # - nh: nicer rebuild/clean/search CLI (`nh os switch`, `nh clean all`),
  #   auto-uses nix-output-monitor for readable, tree-structured build output.
  # - nix-index-database + comma: run any package without installing (`, cmd`)
  #   and a working command-not-found, backed by a prebuilt index (no slow
  #   local generation).
  flake.modules.nixos.nix-tooling = {pkgs, ...}: {
    imports = [inputs.nix-index-database.nixosModules.nix-index];

    programs.nh = {
      enable = true;
      clean = {
        enable = true;
        extraArgs = "--keep 5 --keep-since 7d";
      };
    };

    programs.nix-index-database.comma.enable = true;

    environment.systemPackages = [pkgs.nix-output-monitor];
  };
}
