# Contract only; tests/tuicr/test_wiring.py binds these scenarios to source checks.
Feature: Nix-managed Tuicr reviews

  Scenario: Developer environments provide the review tool
    Given a Home Manager profile for a desktop or the Gemini development container
    When the profile is evaluated
    Then Tuicr is installed from the pinned nixpkgs package
    And Tuicr self-update checks are disabled

  Scenario: Codex discovers the matching Tuicr workflow
    Given Tuicr is enabled in a developer environment
    When Codex scans the user's skills
    Then the Tuicr skill from the packaged source is available under the user skill directory
    And no Codex plugin installation is required

  Scenario: A user starts a working-tree review with a shortcut
    Given the shared shell aliases are loaded
    When the user runs the Tuicr review shortcut
    Then Tuicr opens a review of uncommitted working-tree changes
