# Reviewed PL contract. Unautomated Gherkin unless a scenario names the gate
# that binds it; a scenario is not a test until it fails before the change.

Feature: Repository simplification
  The repository exposes only live operations, every retained test is gated, and
  each finished document has one canonical copy.

  Scenario: Justfile excludes finished migration transitions
    Given the stateful-stack plan declares P1 through P6 complete
    When I run just --list
    Then no recipe name matches discovery-swag-transition
    And no recipe name matches discovery-swag-resume
    And no recipe name matches discovery-swag-finalize
    And no recipe name matches discovery-adguard-transition
    And no recipe name matches discovery-adguard-runtime-split
    And no recipe name matches discovery-docker-scratch
    And no recipe name matches discovery-esp-

  Scenario: Finished P3 drill recipes leave together with their scripts
    Given the P3 secondary-DNS outage proof is complete
    When I run just --summary
    Then no recipe name matches p3-adguard-outage
    And no recipe name matches p3-generic-dhcp-client
    And p3-dns-verify is listed
    And no retained recipe calls a deleted p3 script

  Scenario: A rebuildable one-off records its command before deletion
    Given a recipe has no gate, no runtime reference and no safety token
    When the recipe is deleted as a one-off
    Then the command it ran appears in the named runbook or reference page
    And no retained recipe calls it
    And no sibling repository calls it

  Scenario: Recovery and diagnostic capabilities survive
    Given the simplified justfile
    When I run just --list
    Then discovery-swag-restore-drill is listed
    And discovery-adguard-restore-drill is listed
    And discovery-harbor-restore-drill is listed
    And discovery-haos-boot-drill is listed
    And kepler-recovery-inventory is listed
    And deploy-rs is listed
    And update-safe is listed

  Scenario: Deleted scripts leave no recipe reference
    Given the p3 and stateful-stack scripts are deleted
    When I grep the justfile for each deleted script name
    Then no recipe body matches
    And no retained script sources or copies a deleted script

  Scenario: Every retained test directory is gated
    Given the test tree after triage
    When I run the pre-flight gate
    Then every directory under tests/ is referenced by a CI workflow or a just recipe
    And the gate fails when a new unreferenced directory is added

    Examples:
      | gate              |
      | pull request      |
      | merge candidate   |

  Scenario: Deleted tests cover only removed subjects
    Given a test directory is deleted
    Then no repository file references tests/<deleted-directory>
    And the feature or module it asserted no longer exists in the tree

  Scenario: One canonical record per moved document
    Given a document whose canonical copy lives in the homelab repository
    When I inspect docs/proposals and docs/implemented
    Then no file contains only a Moved pointer
    And each affected README row links the canonical homelab URL

  Scenario: The docs index does not restate status
    Given docs/README.md as the documentation index
    When I compare an index row with its document
    Then the row describes purpose
    And the row contains no status verdict
    And the document's own Status line is the only status record

  Scenario: Unreferenced assets are removed
    Given an asset tracked under config/ or the repository root
    When no tracked file references its path or basename
    Then the asset is not present in the simplified tree

  Scenario: Discovery still evaluates
    Given the stateful-stack module and its helpers are deleted
    When I run just dry discovery
    Then the toplevel evaluates without error
    And no retained option references discovery-stateful-stack-ops

  Scenario: Justfile is split by domain without renaming recipes
    Given the deletion change is complete
    When the split lands
    Then the root justfile declares the variables and imports just/*.just files
    And every recipe is reachable under its previous name
    And the recipe set after the split equals the recipe set before it
    And no justfile uses mod instead of import
