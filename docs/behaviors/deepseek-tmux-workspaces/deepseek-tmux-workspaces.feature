@unautomated
Feature: Persistent DeepSeek Harness workspaces on Gemini
  The operator wants eight concurrent DeepSeek Harness slots per repository
  checkout while one declarative Gemini deployment owns their configuration,
  credentials path, persistence, and remote entry boundary.

  Background:
    Given Gemini is the remote-primary SSH development environment
    And DeepSeek Harness is installed from the pinned package flake
    And runtime credential values remain owned by Vault

  Scenario: Reattach to eight slots for one checkout
    Given a Git checkout exists on Gemini
    When the operator starts its DeepSeek tmux workspace
    Then one named tmux session exposes exactly eight numbered slots
    And rerunning the launcher attaches to the same tmux session
    And disconnecting the SSH client leaves live slot processes running

  Scenario: Separate state by checkout and slot
    Given two checkout paths or two slot numbers are different
    When their Harness homes are resolved
    Then they resolve to different writable directories on the persistent Gemini volume
    And each directory records its checkout identity and slot number
    And every directory consumes the same read-only declarative configuration overlay

  Scenario: Refuse a second writer for one slot
    Given one Harness process owns a checkout slot
    When another TUI, Web, or headless process targets the same slot
    Then the second process exits nonzero before booting Harness
    And the existing session log and settings remain unchanged

  Scenario: Run a fresh task from the CLI
    Given a checkout slot has no live writer
    When the operator runs a headless task in that slot
    Then Harness creates one fresh persisted session
    And prints the final answer to standard output
    And exits with the Harness task result
    And releases the slot writer lock

  Scenario: Resume a persisted conversation from the CLI
    Given a persisted Harness conversation exists
    And the pinned TUI compatibility gate passed
    When the operator starts the TUI in that conversation's slot
    And selects the conversation with /resume
    Then Harness continues the persisted session with its prior history
    And the shipped headless profile remains documented as fresh and one-shot
    And the Web session surface remains the fallback if the TUI gate fails

  Scenario: Select only reviewed models from the CLI
    Given the scoped LiteLLM key permits only deepseek-v4-flash and deepseek-v4-pro
    And a shared DSH OAuth grant authorizes the native openai-codex provider
    When the operator lists models with /model
    Then the list contains deepseek-v4-flash, deepseek-v4-pro, gpt-5.6-sol, gpt-5.6-terra, and gpt-5.6-luna
    And no other model alias is offered by the declarative providers
    And selecting a DeepSeek model routes the next request through LiteLLM
    And selecting a GPT model routes the next request through openai-codex

  Scenario: Share native Codex authentication without sharing conversations
    Given the operator completed the bounded Harness Codex login on Gemini
    When two different checkout slots use a GPT model
    Then both read the same DSH-owned openai-codex OAuth record
    And credential refresh writes are serialized by the credential provider
    And their Harness homes, conversations, settings, and writer locks remain separate
    And neither process reads, copies, or modifies ~/.codex/auth.json

  Scenario: Open a slot Web surface remotely
    Given a checkout slot has no live writer
    When the operator starts its Web profile on an available port
    Then Harness listens only on 127.0.0.1
    And does not open a browser on Gemini
    And the operator reaches it through explicit SSH port forwarding
    And an occupied port causes a fail-closed error

  Scenario: Apply YOLO mode only inside Gemini
    Given a Harness slot starts on Gemini
    When its permission policy is assembled
    Then DSH_PERMISSION_MODE is danger-full-access
    And DSH_TELEMETRY_DISABLED is 1
    And the runbook states that filesystem confinement is disabled
    And no Harness Web port is exposed to the LAN, tailnet, or Internet

  Scenario: Inject scoped runtime credentials without copying them into slot state
    Given Vault holds a DeepSeek-Harness-specific LiteLLM key
    And the shared DSH credential document holds the openai-codex OAuth grant
    When a Harness process starts
    Then the launcher receives the LiteLLM key through its inherited environment
    And the key permits only the two reviewed DeepSeek aliases and budget
    And the native Codex provider reads the shared OAuth record through its configured credential path
    And no slot .credentials.yaml or .env file is required
    And no credential value enters the Nix store, tmux environment, Git, slot state, or backup

  Scenario: Recover after Gemini restart
    Given persisted slot state exists and no Harness process is running
    When Gemini or Orion restarts
    Then rerunning the tmux launcher resolves the same slot directories
    And persisted conversations remain available to Harness
    But shells and in-flight model turns are not claimed to survive the restart

  Scenario: Restore non-secret session state
    Given the scheduled encrypted Restic backup completed
    When one disposable slot is restored into an empty recovery directory
    Then its persisted session can be listed or opened by the pinned Harness build
    And credential files are absent from the restored tree
    And the live slot remains untouched

  Scenario: Keep concurrent repository edits an operator decision
    Given multiple slots may run with danger-full-access
    When two tasks could edit the same files
    Then the launcher does not claim filesystem isolation between slots
    And the runbook directs the operator to existing Git worktrees for independent writes
    And the launcher does not create, remove, or reset worktrees automatically
