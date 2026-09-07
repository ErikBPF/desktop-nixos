# Reviewed contract; unautomated Gherkin (equivalent unittest coverage, no bindings).
Feature: Safe lock candidate
  Scenario Outline: Refuse existing lock edits
    Given flake.lock has <edits> changes
    When the operator runs just update-safe
    Then the command fails before running Nix
    And the lock bytes and Git index remain unchanged
    Examples:
      | edits    |
      | staged   |
      | unstaged |

  Scenario Outline: Restore an unsuccessful candidate
    Given flake.lock is clean with known working-tree bytes
    When just update-safe encounters <failure>
    Then the command fails and restores those exact bytes
    And the Git index remains unchanged
    Examples:
      | failure          |
      | update failure   |
      | dry-build failure|
      | INT during update|
      | TERM during update|
      | INT during build |
      | TERM during build|

  Scenario: Retain a verified candidate
    Given flake.lock is clean
    When update and dry-build both succeed
    Then the candidate lock remains for review
    And the temporary backup is removed
