Feature: Restore bounded cache scheduling while updating Orion safely
  # Unautomated behavior contract. Merged-option unittest checks exercise its
  # configuration requirements; this file has no Gherkin step bindings.

  Scenario: Restore the existing schedule and permit missed-run catch-up
    Given Orion's cache schedule was paused during outage investigation
    And the operator approves immediate missed-run catch-up
    When the reviewed configuration is activated
    Then the existing cache timer is enabled for 03:00
    And persistence permits an overdue run
    And the cache builder retains two-job and two-core hints
    And its aggregate CPU quota remains 400 percent
    And its start and stop limits remain 89 minutes and 1 minute

  Scenario: Preserve recovery and telemetry controls through the update
    Given earlier kernel corruption and checksum failures remain unresolved
    When Orion receives the reviewed update including OpenCode v2
    Then the seven accepted recovery sysctls remain configured
    And normal operating-system sleep remains blocked
    And existing telemetry exclusions and retention remain unchanged
    And no kernel, GPU tuning, firmware, routing, or WOL change is introduced

  Scenario: Publish reviewed source before restoring automatic cache work
    Given the cache warmer and nightly OS upgrade read published main
    When the operator approves publication and merge
    Then the patch is published and merged only after required checks pass
    And deployment uses the reviewed merged source
    And OpenCode state is backed up privately before first v2 use
    And failed build, activation, or fresh health checks stop rollout
