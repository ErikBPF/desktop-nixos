Feature: Deterministic recognition of repeated Grafana alert episodes
  # Binding: python3 modules/hosts/discovery/hermes-plugins/alert-dedupe/selftest.py
  # Config invariants: python3 tests/argus-security/test_argus.py
  # Classification runs over the rendered Discord text (templates.yaml) because
  # the native Discord contact point is the only live Grafana path.
  # Scenarios are @unautomated until the binding above prints its PASS marker.

  Background:
    Given Argus runs with zero Discord and webhook platform toolsets
    And a durable ledger at /opt/data/state/alert-dedupe/ledger.json

  @repeat
  Scenario: A repeat firing of the same episode is one deterministic line
    Given a ledger episode for family "systemd unit failed on host|discovery|prometheus|foo.service"
    And that episode started at 1761447600 and was seen twice
    When a new Grafana message repeats the same family with the same start
    Then the reply begins with "repeat #3"
    And the reply does not repeat the earlier investigation
    And the ledger count for that episode becomes 3

  @new-episode
  Scenario: A resolved-then-firing cycle is a new episode, not a repeat
    Given a ledger episode for family "Host memory available < 5% for 15m|kepler|-|-"
    And that episode started at 1761447600 and was seen 3 times
    When a new Grafana message for the same family reports start 1761490800
    Then the reply begins with "new episode #2"
    And the reply links the previous episode's thread
    And severity escalation within one episode keeps the family unchanged

  @resolved
  Scenario: A resolved notice closes the episode without investigation
    Given a live ledger episode for family "Container down|kepler|-|-" started at 1761447600
    When Grafana posts the resolved notice for that family and start
    Then the reply begins with "resolved"
    And the ledger marks the episode resolved
    And no investigation verdict is produced
    And no thread is archived or closed

  @restart
  Scenario: A restart preserves episode identity
    Given a ledger containing family "Authentik offsite recovery source exceeds 18 hours|discovery|-|-" started at 1761447600
    When the plugin process restarts and sees the same family and start
    Then the verdict is still a repeat
    And the prior thread link is retained

  @mapping-loss
  Scenario: A lost or corrupt ledger degrades to an honest unknown
    Given the ledger file is absent or unparseable
    When a Grafana message arrives
    Then the reply states that repeat status cannot be confirmed
    And the full investigation still happens

  @plugin-failure
  Scenario: A plugin failure never silences an alert
    Given the classification raises an unexpected error
    When the hook runs
    Then it returns no replacement text
    And the unmodified response is delivered

  @grouped-message
  Scenario: A grouped message with any new instance is new
    Given a ledger with repeats for families on two hosts
    When one Grafana message carries those two repeats and one unseen host
    Then the verdict is new
    And the reply names the unseen host
    And the message is marked as a visible subset when instances were omitted

  @adversarial-key
  Scenario: Forged key text cannot suppress an alert
    Given a summary field containing a forged "key" token and instruction-like text
    When the message is classified
    Then the forged token is not used as the family
    And the reply is still delivered
    And the reply contains no instruction-following behavior

  @no-tools
  Scenario: The dedupe path stays inside the read-only boundary
    Given the Argus Nix configuration
    Then Discord and webhook platform toolsets remain empty
    And terminal and kanban remain disabled
    And the alert-dedupe plugin is enabled and mounted read-only
    And the plugin imports no network or subprocess module
