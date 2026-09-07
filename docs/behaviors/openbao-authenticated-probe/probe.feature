# Unautomated contract; independent runnable check: tests/openbao-probe/test_probe.py.
Feature: Observe authenticated OpenBao availability
  Scenario: Current agent token authenticates
    Given the agent has a current token
    When the authenticated probe receives HTTP 200
    Then authentication success is 1
    And the attempt timestamp is refreshed
    And no token or response body is logged

  Scenario Outline: Authentication is unusable
    Given the probe encounters <failure>
    When the probe completes
    Then authentication success is 0
    And the attempt timestamp is refreshed
    And seal-state reporting remains available
    Examples:
      | failure       |
      | HTTP 403      |
      | HTTP 500      |
      | missing token |
