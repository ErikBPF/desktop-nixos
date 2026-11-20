Feature: Orion and Apollo build placement and guest-only KACE
  # Documentary scenarios; runner mappings below are intended, not full coverage claims.
  # Intended mapping: distributed-builds, build-process, update-safe suites.
  Scenario: Recipes build only on Orion
    Given Orion is the only remote build pool member
    When a recipe builds a host closure
    Then every invocation carries `--max-jobs 0`
    And no client host enrolls Apollo
    And Kepler is never a remote builder

  Scenario: A recipe that targets Orion documents the self-build dependency
    Given a recovery recipe targets Orion itself
    When it exports the Orion builder endpoint
    Then the recipe carries a comment that the recovered host must be healthy
    And an operator can override `orion_builder` to use another builder

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

  # Latest clarification retains KACE only in the Ubuntu work guest.
  # Intended mapping: work-profile and work-vm source tests.
  Scenario: KACE remains required only inside the Ubuntu work guest
    When Endeavour source and guest deployment are checked
    Then no KACE package or watchdog is declared on the NixOS host
    And the guest still verifies its apt-owned ampagent package and konea service
    And Cloudflare WARP and Trend Micro guest checks remain
    And the Ubuntu work VM remains configured

  Scenario: Guest KACE is not removed
    Given the Ubuntu work guest still needs KACE
    When the repository's operational entry points are inspected
    Then no guest KACE uninstall helper or recipe is provided
    And no live guest mutation is requested

  Scenario: Published source waits for scheduled cache publication
    When the reviewed correction is merged to main
    Then no manual Orion cache build or host activation is triggered
