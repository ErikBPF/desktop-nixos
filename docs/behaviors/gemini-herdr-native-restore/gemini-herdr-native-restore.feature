@contract @unautomated
Feature: Native OpenCode restore in Gemini Herdr sessions
  Gemini users can resume an OpenCode conversation after a Herdr server
  restart without making agent state multi-writer or persisting pane output.

  Background:
    Given Gemini and its clients use the same pinned Herdr release
    And Gemini remains the sole writer of OpenCode session state

  Scenario: Install the official integration declaratively
    When Home Manager activates the Gemini user profile
    Then the official OpenCode integration from the pinned Herdr source exists at the OpenCode plugin path
    And activation does not run an imperative Herdr integration installer

  Scenario: Preserve the narrow persistence boundary
    When the OpenCode integration is enabled
    Then native agent restore remains enabled
    And Herdr pane-history persistence remains disabled
    And no OpenCode authentication or session database is copied to another host

  Scenario: Enter the managed default session
    When a user invokes the local, direct-remote, or SSH-fallback Herdr alias
    Then the alias targets the boot-enabled homelab session
    And no canonical alias targets an unmanaged code session

  Scenario: Reject a missing or outdated canary
    Given the Gemini profile has been deployed
    When the operator checks Herdr integration status
    Then OpenCode must report a current integration
    And a missing or outdated result blocks the restart proof

  Scenario: Resume one disposable conversation
    Given OpenCode reports a current native integration
    And a disposable OpenCode conversation has reported its session identity
    When the operator restarts only the disposable Herdr test session
    Then Herdr resumes the same OpenCode conversation
    And unrelated Herdr sessions remain running
