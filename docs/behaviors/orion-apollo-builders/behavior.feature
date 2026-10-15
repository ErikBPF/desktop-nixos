Feature: Orion and Apollo build placement and KACE retirement
  # Documentary scenarios; runner mappings below are intended, not full coverage claims.
  # Intended mapping: distributed-builds, build-process, update-safe suites.
  Scenario: Deployments use only eligible remote builders
    Given Orion and Apollo are the remote build pool
    When a target-specific build is requested
    Then Kepler is never a remote builder
    And the target is excluded from its own remote pool

  Scenario: Ordinary builds prefer remote capacity with bounded fallback
    Given an ordinary derivation supports a remote builder
    And the derivation does not request preferLocalBuild
    When an eligible remote slot is available
    Then Nix attempts remote execution before local execution
    But unavailable eligible capacity permits one local job
    And a failed accepted remote compilation remains a failure

  Scenario: Explicit recipe overrides survive nested Just calls
    Given an operator supplies builder overrides
    When a recipe invokes the builder selector through a child Just process
    Then the child uses the supplied overrides

  Scenario: Kepler and Discovery use dedicated credentials
    Given each server has its own encrypted builder credential
    When its daemon connects to Orion or Apollo
    Then only the restricted Nix builder endpoint accepts the credential
    And unknown or changed SSH host keys never authenticate
    And personal SSH private keys are not copied to the servers

  # KACE retirement from Endeavour and its Ubuntu guest.
  # Intended mapping: work-profile tests and guest-removal workflow checks.
  Scenario: Active configuration no longer requires KACE
    When Endeavour source and guest deployment are checked
    Then no active KACE package or watchdog is declared or required
    And Cloudflare WARP and Trend Micro guest checks remain
    And the Ubuntu work VM remains configured

  Scenario: Guest removal targets only the retired agent package
    Given the Ubuntu work guest owns the retired ampagent package
    When the documented removal workflow is authorized and run
    Then the agent package is removed without purging unrelated data
    And no backup or extra pre-removal validation is required
    And historical receipts and immutable rollback generations remain
