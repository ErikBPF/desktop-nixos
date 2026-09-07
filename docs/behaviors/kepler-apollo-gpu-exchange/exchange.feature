@contract @unautomated
Feature: Exchange Kepler and Apollo GPUs without losing host services
  Background:
    Given the operator selected moving Kepler's NVIDIA card to Apollo
    And Apollo's currently AMD-driven card is selected for Kepler

  Scenario: Confirm the hardware before changing boot configuration
    Given both hosts still contain their original cards
    When inventory is collected
    Then PCI vendor and device identities and bound drivers are recorded
    And no driver is replaced and no workload is stopped

  Scenario: Preserve Kepler infrastructure through the exchange
    Given reviewed driver generations and a staffed physical exchange window
    When Kepler boots with the replacement AMD card
    Then its GPU binds to the accepted AMD driver
    And the accepted Kepler configuration has no NVIDIA-specific runtime dependency
    And its storage and Kubernetes substrate pass their existing acceptance checks
    And its kernel hold and virtual-machine placement remain unchanged

  Scenario: Preserve the NVIDIA card's stability policy on Apollo
    Given the exchanged NVIDIA card has recorded workload faults
    When Apollo boots its reviewed NVIDIA configuration
    Then the existing conservative power and clock limits apply
    And a bounded workload test is required before inference acceptance

  Scenario: Keep workload routing separate from a successful hardware boot
    Given household inference placement has not been selected
    When the GPU exchange is prepared
    Then no household inference route is moved automatically
    And missing inference remains visible in its existing alert

  Scenario: Recover from failed acceptance
    Given original hardware identities and compatible boot generations are recorded
    When the exchanged configuration fails driver or host-service acceptance
    Then later workload cutover stops
    And the staffed recovery procedure restores a compatible hardware and boot combination

  Scenario: Suspend household inference while replacing the GPU
    Given the operator selected a temporary household inference pause
    When the accepted Kepler generation is prepared
    Then Whisper, HA Qwen and retrieval are excluded from automatic stack startup
    And model data and service definitions are retained
    And no household workload is automatically started on Apollo
