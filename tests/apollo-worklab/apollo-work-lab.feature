@contract @unautomated
Feature: Apollo native work lab and host control plane
  Apollo is the single persistent development host, projects own their
  toolchains, and the host keeps its own work state on local disks.

  Background:
    Given Endeavour is an authorized administration client
    And Apollo is enrolled in the private network

  Scenario: Resume one persistent work session
    Given the named work session is running on Apollo
    When Endeavour disconnects and reconnects to Apollo
    Then the same editor, shell, and supported agent processes are visible
    And no nested terminal multiplexer is required

  Scenario: Let each project select its toolchain
    Given a project declares its supported development environment
    When the operator enters that project environment on Apollo
    Then the project language and build commands are available
    And Apollo does not select their versions through host language modules

  Scenario: Keep frequent control tools immediately available
    When the operator logs in to Apollo
    Then Kubernetes, Nix, host, storage, and network control commands are available
    And "stern" and "nvd" are available without changing the system generation
    But rare kernel diagnostics do not require permanent host packages

  Scenario: Diagnose the complete work lab without exposing secrets
    When the operator runs the Apollo work-lab diagnosis
    Then it reports host capacity and failed critical units
    And it reports Herdr, Syncthing, and Orion cache health
    And it does not print credentials, private keys, tokens, or kubeconfig data

  Scenario: Use the canonical Orion cache path
    Given Orion's Nix cache is healthy on the private network
    When Apollo requests "http://orion:5000/nix-cache-info"
    Then the request succeeds without waiting for fallback

  Scenario: Administer the host noninteractively
    Given Endeavour authenticated to Apollo with an authorized public key
    When the operator invokes sudo
    Then sudo does not prompt for a password
    And default coding-agent aliases do not bypass approval or sandbox controls

  Scenario: Keep one writer for synchronized work
    Given project folders have converged on Apollo
    When Apollo becomes the remote-primary work host
    Then Apollo is the only active writer for those synchronized folders
    And Gemini is no longer a synchronization peer for those folders
    And Endeavour retains a receive-only versioned mirror

  Scenario: Refuse a seed that would fill temporary storage
    Given Apollo still uses the 240 GB system RAID1 for work folders
    When the selected folders cannot be seeded while leaving 20 percent free
    Then the writer remains unchanged
    And the cutover waits for a smaller folder set or the workload SSDs

  Scenario: Keep mutable agent credentials local
    When project folders synchronize between Apollo and Endeavour
    Then Codex, Claude Code, and OpenCode mutable state is not synchronized
    And credentials are not copied as project data

  Scenario: Drop Gemini with its retired cluster
    Given Apollo has passed live cutover acceptance
    And Gemini's development container and its k3s cluster were retired on 2026-09-07
    Then no recipe, unit, or container definition targets Gemini
    And Gemini does not run the primary Syncthing or Herdr duties
