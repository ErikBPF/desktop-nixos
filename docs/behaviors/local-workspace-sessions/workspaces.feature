Feature: Independent local project windows
  Each application has its own desktop window and named tmux session.

  Scenario: Create independent default windows
    Given each project's default tmux sessions are absent
    When recovery initializes the desktop
    Then workspace 2 has six dataplatform coding-agent windows and two shell windows
    And workspace 7 has six homelab coding-agent windows and two shell windows
    And each window attaches to a different single-pane tmux session
    And workspaces 3 and 8 each have independent tuicr and Neovim windows
    And all twenty sessions start in their project's local directory

  Scenario: Use the configured coding agent
    Given defaultCodingAgent selects another installed executable
    When a missing coding session is created
    Then it runs that executable without permission-bypass flags
    And normal application exit returns to an interactive shell

  Scenario: Preserve existing work
    Given a named tmux session already exists with user changes
    When recovery is requested
    Then the session's processes and layout are preserved
    And no commands are replayed into its panes

  Scenario: Keep the backend independent of windows
    Given the dedicated tmux service is not yet ready
    When a frontend initializes its session
    Then it waits for the backend within a fixed bound
    And it never starts another tmux daemon
    And closing a frontend does not terminate its session

  Scenario: Route new terminal applications
    When shell, Neovim, or Yazi is launched through a desktop shortcut
    Then workspaces 2 through 4 use the dataplatform directory
    And workspaces 5 through 12 use the homelab directory
    And other workspaces retain their previous behavior
    And mapped Yazi launches ignore the global saved directory

  Scenario: Recover windows without duplicates
    Given some or all default windows are already open
    When login or Super+Shift+R requests recovery repeatedly or concurrently
    Then existing window and session identities remain unchanged
    And missing windows attach to their named sessions

  Scenario: Preserve deployed Herdr work during the correction
    Given the previous four Herdr backends are running
    When the independent tmux configuration is activated
    Then the old Herdr attachment windows may close
    But the old Herdr backend processes are not stopped
    And other hosts and the default tmux socket are unchanged
