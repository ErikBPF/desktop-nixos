{inputs, ...}: {
  # comma (`, <cmd>` runs any package without installing) + command-not-found,
  # backed by a prebuilt index. Desktop-only: headless servers don't need
  # run-anything, and the index DB is dead weight in their closure.
  flake.modules.nixos.nix-index = {...}: {
    imports = [inputs.nix-index-database.nixosModules.nix-index];
    programs.nix-index-database.comma.enable = true;
  };
}
