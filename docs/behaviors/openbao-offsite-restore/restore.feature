Feature: Prove OpenBao recovery from the Voyager backup
  # Unautomated Gherkin contract; executable checks are mapped in test-contract.md.

  Scenario: Restore the selected remote source
    Given Voyager contains an OpenBao snapshot whose source file is less than 48 hours old
    When the existing recovery drill selects that remote snapshot
    Then retrieval uses its exact full snapshot identifier
    And the isolated node restores, unseals and accepts AppRole authentication
    And the receipt identifies Voyager, the snapshot and source timestamp
    And private scratch is removed

  Scenario Outline: Reject invalid recovery input
    Given the remote source is <input>
    When the recovery drill runs
    Then no isolated restore starts
    And prior success evidence is unchanged
    And private scratch is removed
    Examples:
      | input |
      | unavailable |
      | absent |
      | ambiguously selected |
      | not a regular file |
      | empty |
      | future dated |
      | exactly 48 hours old |
      | older than 48 hours |

  Scenario: A downloaded snapshot cannot recover the application
    Given the selected source is fresh but restore, unseal or authentication fails
    When the isolated verification runs
    Then prior success evidence is unchanged
    And private scratch and the isolated process are removed

  Scenario: Preserve production and the existing schedule
    Given the quarterly drill is enabled
    When it runs or is interrupted
    Then production OpenBao storage and endpoints are not modified
    And no local snapshot fallback is used
    And the quarterly cadence is unchanged
