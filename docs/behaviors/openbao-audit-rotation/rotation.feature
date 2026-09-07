# Reviewed unautomated contract; equivalent executable test, no Gherkin bindings.
Feature: Audit rotation inside the service ownership boundary
  Scenario: Continue auditing after rotation
    Given OpenBao writes private HMAC-protected audit events
    When logrotate renames the audit file and signals SIGHUP without creating a replacement
    Then OpenBao creates its own mode 0600 audit file
    And authenticated requests succeed and are audited

  Scenario: Fail closed on an unwritable replacement
    Given a replacement audit file cannot be written by OpenBao
    When OpenBao reopens the audit device
    Then authenticated requests fail with HTTP 500

  Scenario: Recover an empty file without destroying evidence
    Given an active DynamicUser OpenBao has an empty mode 0600 audit file with incorrect mapped ownership
    When the operator repairs ownership inside the service mount namespace
    Then the file contents and permissions remain unchanged
    And SIGHUP resumes auditing
