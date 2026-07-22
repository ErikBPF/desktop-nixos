{inputs, ...}: {
  flake.modules.home.claude-code = {
    config,
    lib,
    pkgs,
    ...
  }: {
    home.packages = [pkgs.claude-code];

    home.activation.installClaudePonytail = lib.hm.dag.entryAfter ["installPackages"] ''
      if ! ${config.home.profileDirectory}/bin/claude plugin list --json |
        ${lib.getExe pkgs.jq} -e 'any(.[]; .id == "ponytail@ponytail")' >/dev/null; then
        run ${config.home.profileDirectory}/bin/claude plugin marketplace add ${inputs.ponytail} --scope user
        run ${config.home.profileDirectory}/bin/claude plugin install ponytail@ponytail --scope user
      fi
    '';
  };
}
