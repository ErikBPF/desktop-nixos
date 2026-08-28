@unautomated
Feature: Kepler returns safely after a cold restart
  Kepler must remain diagnosable and must not redirect pool-backed bind writes
  to the OS disk when a ZFS data pool is absent during boot.

  Background:
    Given Kepler uses ZFS dataset "fast-pool/data" at "/fast"
    And Kepler uses ZFS dataset "bulk-pool/data" at "/bulk"
    And SSH and Tailscale do not require either data pool

  Scenario: Return the complete host after a forced power cycle
    Given both expected ZFS datasets are mounted and ONLINE
    And the operator forces Kepler off without an orderly shutdown
    And Kepler remains powered off for two minutes
    When the operator powers Kepler on
    Then SSH and Tailscale become reachable
    And every declared Compose stack starts in its declared order
    And every declared MicroVM starts from "/fast/microvms"
    And the k3s control plane and platform reconcilers report healthy
    And workload reconciliation is reported separately
    And the operational-return verdict passes within 10 minutes of power-on

  Scenario Outline: Start a stack only with its required storage
    Given <available storage> is mounted with the expected ZFS identity
    When the <stack> Compose unit is started
    Then the start result is <result>
    And no bind data is written below an absent required mountpoint

    Examples:
      | stack       | available storage | result  |
      | infra       | /fast and /bulk    | started |
      | buzz        | /fast and /bulk    | started |
      | monitoring  | neither pool       | started |
      | sync        | /fast and /bulk    | started |
      | security    | /fast              | started |
      | whisper-gpu | /fast              | started |
      | qwen4b-gpu  | /fast              | started |
      | infra       | /fast only         | blocked |
      | buzz        | /bulk only         | blocked |
      | sync        | neither pool       | blocked |
      | security    | neither pool       | blocked |
      | whisper-gpu | neither pool       | blocked |
      | qwen4b-gpu  | neither pool       | blocked |

  Scenario: Reject a lookalike mount directory
    Given "/fast" exists as a directory on the OS filesystem
    But "fast-pool/data" is not mounted there as ZFS
    When a stack requiring "/fast" is started
    Then the stack is blocked before Compose runs
    And the failure identifies the expected dataset and mountpoint without secret values

  Scenario: Keep degraded boot remotely recoverable
    Given one expected ZFS pool is unavailable during boot
    When Kepler reaches its normal system target
    Then SSH, Tailscale, and storage diagnostics remain available
    And only stacks whose requirements are satisfied may start
    And the unavailable pool does not cause the current OS generation to be demoted

  Scenario: Return known desired state while the Servarr remote is unavailable
    Given the existing Kepler Servarr checkout is clean and was previously activated
    And GitHub or its network path is unavailable
    When the declared Compose stacks are considered for startup
    Then the existing checkout is validated and may supply their desired state
    And the checkout is not rewritten or switched to another branch
    And source-sync reports degraded without making operational-return fail

  Scenario Outline: Reject untrusted local desired state while offline
    Given the Servarr remote is unavailable
    And the local Kepler desired state has <invalid state>
    When the declared Compose stacks are considered for startup
    Then stacks depending on that desired state are blocked
    And no remote branch or alternate checkout is selected
    And source-sync identifies the invalid state without emitting values

    Examples:
      | invalid state                |
      | no exact v2 pin              |
      | a malformed exact v2 pin     |
      | a pin for another machine    |
      | a dirty tracked file or index |
      | a checkout at another commit |
      | a checkout with another tree |

  Scenario: Recover a pool that becomes available after boot
    Given a required pool was unavailable and its dependent stacks were blocked
    And the expected ZFS dataset is now mounted and ONLINE
    When the operator invokes the documented storage recovery
    Then only affected units are reset and started in declared order
    And their expected containers and health checks pass
    And invoking the same recovery again creates no duplicate owner and performs no unnecessary recreation

  Scenario: Preserve the existing MicroVM storage boundary
    Given "fast-pool/data" is not mounted at "/fast"
    When the k3s MicroVM units are considered for startup
    Then no MicroVM starts against a directory on the OS filesystem

  Scenario: Report an exact reboot-return failure
    Given Kepler has returned to SSH
    But a required pool, declared unit, intended container, MicroVM, cluster gate, or recovery-evidence gate fails
    When the reboot-return verifier completes
    Then it reports a degraded result
    And it identifies the failed gate and documented recovery entrypoint
    And it emits no environment or secret value

  Scenario: Separate host return from disaster-recovery readiness
    Given SSH, storage, declared runtimes, and the k3s control plane have returned
    But restore evidence is stale or missing
    When the reboot-return verifier completes
    Then operational-return passes
    And recovery-readiness reports degraded

  Scenario: Prove non-rebuildable state recovery
    Given every Kepler bind mount and named volume is inventoried
    When cold-restart resilience is accepted
    Then each state owner is classified as rebuildable, accepted-loss, or restore-tested
    And local and offsite Buzz restore evidence is no more than nine days old
    And reboot survival alone is not accepted as restore proof

  Scenario: Repeat verification without mutation
    Given Kepler state has not changed since a completed reboot-return check
    When the verifier runs again
    Then it returns the same verdict
    And it does not restart units, recreate containers, import pools, or change boot selection

# Contract only: unautomated until scenarios are bound to runnable checks and
# observed failing before implementation.
