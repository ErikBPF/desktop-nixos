# VS Code formatting and linting configuration

**Stage / revision:** GREEN / 3
**Status:** partial — source validated and user generation built; activation awaiting scope approval
**Owner / date:** desktop-nixos / 2026-11-27
**Checkout:** `worktrees/vscode-format-lint-20261127`, branch `chore/vscode-format-lint-20261127`, based on `a63bd64d`

## Outcome and why

Human seed, verbatim:

> check our extension list in vscode and lets remove copilot and anything that is used to debug code. We use it now only for formating and linting

The declarative extension list now has 11 entries instead of 24. Copilot is bundled with the installed VS Code package rather than declared in the marketplace list, so the configuration disables its built-in AI features and disables the bundled Copilot and debugger extensions through the package's launch arguments.

## Changes

- Keep Ruff, Black, isort, Nix IDE, YAML, Even Better TOML, Markdown All in One, English and Brazilian Portuguese spell checking, Tokyo Night, and Material Icon Theme.
- Remove Gherkin/Behave tooling, GitLens, Makefile Tools, the three remote-access extensions, Mermaid/SVG/image/CSV previews, color highlighting, Protobuf highlighting, and the redundant JSON outline extension. Built-in JSON formatting remains available.
- Disable `GitHub.copilot-chat`, `vscode.debug-auto-launch`, `vscode.debug-server-ready`, `ms-vscode.js-debug`, and `ms-vscode.js-debug-companion` on launch. Set `chat.disableAIFeatures` to true.
- Remove settings for retired development integrations. Preserve existing formatter selections and save behavior.

The shared module affects Endeavour, Pathfinder, and Apollo. No remote host activation is included.

## Evidence and limits

- Before editing, an assertion requiring `chat.disableAIFeatures` failed because the setting was absent. After editing, it passed.
- The retained extension manifests contain no debugger contributions or `Debuggers` category.
- `just lint`, `just fmt-check`, and `git diff --check` passed.
- The final three-host toplevel `nix build ... --dry-run` exited 0. It also reported an unrelated NVIDIA store path it did not know how to build; this does not establish that a full-system build would succeed. Receipt: `/tmp/vscode-format-lint-20261127-dry.log`.
- The Endeavour Home Manager activation package built successfully through the configured builder: `/nix/store/78ajj24k3yh4jh96gi6pv479h6agck7v-home-manager-generation`. Its extension registry has exactly 11 entries, its settings disable AI, and its VS Code wrapper contains all five disable-extension arguments.
- The canonical repository's `graphify update .` completed with no topology changes. Nix configuration is verified from source and evaluation, not from graph extraction.
- These checks do not establish observed editor behavior or measured RAM savings.

## Continuing work and recovery

The canonical checkout has unrelated changes and is behind its tracked remote; this task uses a separate clean worktree. The active editor still uses its existing generation until the configuration is activated and VS Code is restarted.

**Q-VSCODE-ACTIVATION-1:** Asked through the native asynchronous question UI against this checkout, revision 2, and the prepared generation above. No tuicr session applies. Applying `just home-switch endeavour` also enables a pending Kindle auto-eject service/timer from existing main-branch changes and changes generated font configuration. Other changed Quickshell/wallpaper symlink targets have identical content. Recommendation: retain the prepared VS Code changes for the next planned rebuild unless the user approves the broader user-environment activation. Only activation is waiting; source changes and validation are complete. No response or timeout grants approval.

Revision 3: the user requested, verbatim, “create pr and show me”. This authorizes committing and publishing the task branch for review; it does not answer the pending activation question. The PR contains only the two VS Code configuration files and this validation record.

Recovery is restoring the previous two VS Code configuration files and activating through the owning Home Manager recipe. Disabled tools can be restored from the previous declarative list. No credentials, extension data, or editor documents are deleted.
