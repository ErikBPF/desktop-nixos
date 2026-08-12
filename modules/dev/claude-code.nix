{inputs, ...}: {
  flake.modules.home.claude-code = {
    config,
    lib,
    pkgs,
    ...
  }: {
    home = {
      packages = [pkgs.claude-code];
      file.".claude/AGENT_POLICY.md".source = ./agent-policy.md;
    };

    home.activation.includeClaudeAgentPolicy = lib.hm.dag.entryAfter ["writeBoundary"] ''
      claude_instructions="$HOME/.claude/CLAUDE.md"
      if [[ -f "$claude_instructions" ]] &&
        ! ${lib.getExe pkgs.gnugrep} -Fxq '@AGENT_POLICY.md' "$claude_instructions"; then
        run ${lib.getExe pkgs.gnused} -i '1i@AGENT_POLICY.md' "$claude_instructions"
      fi
    '';

    home.activation.installClaudePonytail = lib.hm.dag.entryAfter ["installPackages"] ''
      if ! ${config.home.profileDirectory}/bin/claude plugin list --json |
        ${lib.getExe pkgs.jq} -e 'any(.[]; .id == "ponytail@ponytail")' >/dev/null; then
        run ${config.home.profileDirectory}/bin/claude plugin marketplace add ${inputs.ponytail} --scope user
        run ${config.home.profileDirectory}/bin/claude plugin install ponytail@ponytail --scope user
      fi
    '';
  };
}
