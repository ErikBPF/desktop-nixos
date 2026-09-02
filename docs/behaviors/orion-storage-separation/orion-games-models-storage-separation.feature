@unautomated
Feature: Orion isolates games from model storage
  Steam and model serving use different physical filesystems without changing
  Orion's established model path.

  Background:
    Given Orion serves models from "/opt/models"
    And Steam sees its library at "/home/erik/.local/share/Steam"
    And the reviewed game disk is mounted at "/games"

  Scenario: Keep model serving unchanged after game separation
    Given the production model is healthy before the storage change
    When Steam is moved to the reviewed game disk
    Then the production model still resolves below "/opt/models"
    And the model service remains healthy without a model-path change

  Scenario: Run Steam from the dedicated game filesystem
    Given the Steam tree was copied to "/games/Steam"
    And the copied byte and file inventory matches the source
    When the declarative Steam bind is activated
    Then "/home/erik/.local/share/Steam" resolves to "/games/Steam"
    And Steam launches successfully
    And the old Steam copy remains available for rollback

  Scenario: Fail Steam closed when the game disk is absent
    Given the reviewed game filesystem is not mounted at "/games"
    When Orion reaches its normal boot target
    Then SSH, Tailscale, and the model service remain available
    And the Steam bind is not mounted
    And Steam does not start
    And no game data is written to the OS filesystem below "/games"

  Scenario: Reject a lookalike game mount
    Given "/games" is a plain directory on the OS filesystem
    When the Steam storage gate runs
    Then the game filesystem is reported missing
    And the Steam bind and Steam startup remain blocked

  Scenario: Reject an unexpected disk identity
    Given a block device does not match the reviewed game-disk identity
    When the storage preparation gate runs
    Then no filesystem is created or modified
    And every existing Orion disk remains unchanged

  Scenario: Refuse unclassified cleanup
    Given a cleanup candidate has no recorded owner or data classification
    When Orion storage cleanup is prepared
    Then the candidate remains unchanged
    And no broad recursive deletion is executed

  Scenario: Reclaim space without losing protected data
    Given cleanup candidates are classified as protected, archived, rebuildable, or cache
    When one approved candidate class is cleaned
    Then free space is measured before and after that class
    And protected and unclassified data remain unchanged
    And required Orion services pass their health checks

  Scenario: Preserve rollback across cache cleanup
    Given a live workload owns disposable cache data
    When that cache is selected for cleanup
    Then the owning workload is quiesced before its cache changes
    And required state and evidence remain available
    And the workload passes its restart and correctness proof

  Scenario: Roll back the Steam bind
    Given the prior Nix generation and old Steam copy are retained
    When the new game filesystem fails its launch or reboot proof
    Then the prior generation restores the old Steam bind
    And the model service remains on "/opt/models"
