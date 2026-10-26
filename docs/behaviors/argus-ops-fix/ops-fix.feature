Feature: Bounded autonomous fixes for Argus
  # Binding: python3 modules/services/ops-fix/selftest.py
  # Binding: python3 modules/hosts/discovery/hermes-plugins/ops-fix/selftest.py

  Scenario: A repeat of an allowlisted alert may restart the container once
    Given the alert ledger says the episode is a repeat
    And the payload names prowlarr
    When Argus calls ops_fix restart_container prowlarr
    Then the runner executes docker restart prowlarr
    And records one audit line
    And a second call within 30 minutes is refused

  Scenario: A non-allowlisted target is refused without execution
    When Argus calls ops_fix restart_container hermes-argus
    Then the runner refuses the request
    And nothing is restarted

  Scenario: An unsupported action is refused by the tool
    When Argus calls ops_fix shell anything
    Then the tool returns an error result
    And the runner is never contacted

  Scenario: A missing runner does not break the turn
    Given the runner socket is absent
    When Argus calls ops_fix status prowlarr
    Then the tool returns an error result
    And the reply is still delivered

  Scenario: The tool surface stays narrow
    Then the Discord toolset is exactly ops_fix
    And the webhook toolset is empty
    And no terminal or file tool is exposed
