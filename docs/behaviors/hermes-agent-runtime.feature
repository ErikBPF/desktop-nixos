Feature: Scoped Hermes image and native consumer compatibility
  # Binding: python3 tests/hermes-agent-runtime.py
  # --new-only excludes OLD image/state gates; never prints full-runtime PASS.

  Scenario: Argus and Romozinha use the verified official release image
    Given the public Discovery image configuration
    Then both profiles pin the verified v0.21.7 immutable manifest index
    And the native image reports v0.21.7 and embedded stable release commit
    And OLD reports v0.21.0 and embedded original image revision
    And Daedalus remains outside this upgrade

  Scenario: Native route admits only known lifecycle states
    Given the actual configured Argus filter and native WebhookRouteProcessor
    Then firing and resolved are admitted
    And missing, null and unknown statuses are rejected

  Scenario: Recovery evidence survives native raw truncation
    Given a synthetic payload larger than 4000 characters
    When the native webhook prompt renderer renders the configured template
    Then groupKey, status, receiver and externalURL survive outside RAW
    And RAW is exactly the native first 4000 characters
    And resolved remains RECOVERY UNVERIFIED
    And automatic incident closure or archival is forbidden

  Scenario: Native in-memory delivery identity preserves retry and episode boundaries
    Given the actual profile-route-delivery identity dataclass and adapter admission helper
    Then a same-ID retry is rejected within one hour
    And resolved with a different ID is accepted
    And a new episode and unchanged repeat with new IDs are accepted
    And other profiles and routes remain isolated
    And expiry and restart admit the ID again

  Scenario: Every interpolated payload value is preceded by the untrusted cue
    Given synthetic group, receiver and source URL scalars containing newlines, quotes, backticks and instruction-like text
    When the actual native renderer renders the Argus template
    Then the initial cue labels all interpolated metadata and RAW as untrusted evidence, not instructions
    And the cue forbids that evidence from authorizing actions or establishing recovery
    And the cue precedes every payload interpolation for benign and adversarial input
    And scalar values remain literal rather than falsely claimed escaped
    And RAW retains native JSON rendering and truncation

  Scenario: Native plugin discovery and terminal caller consume plugin directives
    Given only public plugins in an isolated empty Hermes home
    When the real plugin manager discovers configured plugins
    Then native transform callbacks preserve quoted evidence and remove unquoted leakage
    And the real NEW terminal pre-tool caller consumes the RTK modify directive
    And the real OLD middleware caller consumes the directive before a synthetic guard veto
    And only the synthetic rewrite-command boundary is doubled
    And harmless echo is the only executed command

  Scenario: Synthetic state upgrade and safe-copy downgrade
    Given both immutable native images are available locally
    And the OLD public SessionDB creates a synthetic session and message
    When NEW reopens a disposable copy and appends a message
    Then OLD can read the upgraded copy without writes and append on another safe copy
    And SQLite integrity remains valid
    And OLD native hook compatibility is checked
    # Synthetic constructor-created schema only; no production historical-state coverage.
