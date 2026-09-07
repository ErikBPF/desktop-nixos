# Manual behavior contract; no automated step bindings or claimed test pass.
# Acceptance record: docs/reference/vault-disaster-recovery.md#recovery-custody-acceptance
Feature: Recovery custody survives loss of the home and primary operator
  Scenario: Existing software does not establish physical custody
    Given the passphrase-sealed age-key escrow tooling already exists
    And an encrypted age-key blob exists on the workstation
    When custody evidence is reviewed
    Then outside-home offline passphrase custody remains pending without an operator witness
    And second-custodian readiness remains pending without independent retrieval evidence

  Scenario: Witnessed custody closes the corresponding human gate
    Given the operator has confirmed an offline passphrase copy outside the home
    And a designated second custodian has agreed to the recovery role
    When the custodian witnesses recovery access without the primary operator or home services
    Then the custodian can retrieve the private encrypted age-key blob and offline passphrase
    And the custodian can access the encrypted bootstrap material and recovery instructions
    And the controlled recovery check confirms the recovered key decrypts the bootstrap material
    And the acceptance record contains only role aliases, dates, and outcomes

  Scenario Outline: Circular access does not pass acceptance
    Given recovery access requires <unavailable dependency>
    When recovery custody is assessed
    Then custody remains pending
    And working backups or a local escrow comparison do not override that result

    Examples:
      | unavailable dependency                             |
      | logging into the lost home fleet                    |
      | the primary operator to unlock the password manager |

  Scenario: Custody work preserves the existing secret boundary
    Given the encrypted escrow and SOPS bootstrap store already exist
    When the custody handoff is prepared
    Then no secret value, precise storage location, or credential locator is recorded
    And no escrow ciphertext is published in Git
    And no new root token, key rotation, secret store, or policy change is authorized
