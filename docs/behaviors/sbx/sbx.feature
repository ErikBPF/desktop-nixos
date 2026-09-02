# Contract only; tests/sbx/test_profile.py binds source-level requirements.
Feature: Repository-local Docker Sandboxes tooling

  Scenario: The pinned SBX package builds reproducibly
    Given an x86_64 Linux checkout of desktop-nixos
    When the user builds the sbx flake package without ambient unfree flags
    Then Nix fetches Docker Sandboxes 0.39.0 from docker/sbx-releases
    And only the docker-sbx package receives a local unfree allowance
    And the resulting sbx CLI reports version 0.39.0

  Scenario: Codex runs against an isolated bounded workspace
    Given the user starts SBX from this repository
    When SBX loads the repository environment file
    Then the Codex agent works from a clone instead of the live checkout
    And the sandbox is limited to 4 CPUs and 8 GiB of memory
