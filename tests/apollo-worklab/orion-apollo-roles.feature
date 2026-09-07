@contract @unautomated
Feature: Separate primary hosts for homelab and work development
  The 2026-09-07 user-directed destination assigns homelab work to Orion
  and work or production-analog development to Apollo.
  Repo transfer mechanisms and reboot recovery remain separate decisions.

  Scenario Outline: Enter the primary development host through its umbrella
    Given an authorized client requests its primary "<purpose>" workspace
    When the operator opens that workspace
    Then its terminal runs on "<host>"
    And its initial working directory is the "<umbrella>" repository

    Examples:
      | purpose | host   | umbrella     |
      | homelab | Orion  | homelab      |
      | work    | Apollo | dataplatform |

  Scenario: Keep several tasks rooted in the same umbrella
    Given two task sessions start from the same umbrella repository
    When one task delegates implementation to a sister repository
    Then the umbrella remains the entry point for that task session
    And the other session can display a different task at the same time

  Scenario: Resume work after a client disconnect
    Given a development session is running on its primary host
    And that host and its session service remain running
    When the client disconnects and later reconnects to that session
    Then the same shell and running task remain available

  Scenario: Keep selected repositories available on both machines
    Given the operator has selected personal and work repositories for both hosts
    When repository provisioning completes
    Then each selected repository is a local Git checkout on Orion and Apollo
    And build or deployment commands do not read another machine's working tree
