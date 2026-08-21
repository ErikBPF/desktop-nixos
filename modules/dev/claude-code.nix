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
      file.".claude/skills/codehero".source = ./codex-skills/codehero;
      file.".claude/skills/grill".source = ./codex-skills/grill;
      file.".claude/skills/ip".source = ./codex-skills/ip;
      file.".claude/skills/map".source = ./codex-skills/map;
      file.".claude/skills/party".source = ./codex-skills/party;
      file.".claude/skills/pl".source = ./codex-skills/pl;
      file.".claude/skills/rv".source = ./codex-skills/rv;
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
