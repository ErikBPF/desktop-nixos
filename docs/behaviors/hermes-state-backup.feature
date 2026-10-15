Feature: Scoped encrypted Hermes state backup and isolated rehearsal
  # Human seed: "Authorize scoped backup": two agents, sanctioned Restic
  # repository, isolated restore, then pre-upgrade backup. No live restore
  # without fresh confirmation. Code-phase execution is synthetic only.

  Scenario: Read-only preflight identifies failure phases without lifecycle actions
    When the operator invokes preflight-discovery-hermes-kepler
    Then credential retrieval stays inside private backup-engine storage
    And repository authentication uses snapshot listing with no lock and discarded output
    And the pinned interpreter checks only fixed source filesystem and selected unit metadata
    And no writer or timer is stopped or started on success or failure
    And no backup, dump, database query, or remote store copy occurs
    And only complete preflight reports PASS hermes-state-preflight
    And failures report only static phase and allowlisted exception class and integer command return code
    And unobserved remote failures remain remote-unobserved without guessed quiescence
    And unsafe SSH output and exception messages are never reported

  Scenario: Backup includes exactly both complete homes while writers are quiesced
    Given the declared Argus and Romozinha homes and valid existing authentication
    And the exact flake-pinned Python closure is available at its validated absolute store path
    And both databases are regular files with no unsafe SQLite sidecar links
    When the operator invokes backup-discovery-hermes-kepler
    Then health timers stop before health services and container writers
    And all loaded selected units are confirmed inactive before native tar runs
    And Btrfs subvolumes and database WAL and SHM files are included
    And symlinks are preserved without following them
    And Restic encrypts the archive in the existing sanctioned repository
    And exact-length framing completes without requiring EOF from the still-running SSH supervisor
    And the exact backup-result snapshot is restored only into helper-created isolation
    And both full homes compare byte-for-byte before read-only SQLite integrity checks
    And only previously active writers and timers resume before success is reported

  Scenario Outline: Failed operation still attempts recovery and never reports success
    When <operation> fails or receives a catchable interruption
    Then all previously active writers and timers receive recovery attempts
    And previously inactive units are not started
    And failure and failed recovery remain nonzero
    Examples:
      | operation       |
      | timer stop      |
      | health drain    |
      | writer stop     |
      | tar archive     |
      | Restic backup   |
      | Restic dump     |
      | restore compare |
      | recovery start  |
      | SIGTERM         |
      | restore timeout |
      | invalid frame   |
      | truncated frame |
      | trailing frame  |

  Scenario: Isolated rehearsal has no live lifecycle actions
    Given a full hexadecimal snapshot ID with the exact backup tag and archive scope
    When the operator invokes rehearse-discovery-hermes-kepler with that snapshot
    Then extraction and read-only database integrity run only in fresh isolation
    And no units change state
    And changed live homes are not compared with the historical snapshot

  Scenario: Inputs and failures do not escape scope or disclose private state
    Given invalid IDs, unexpected unit states, unsafe source ancestors, or missing authentication
    Then dependent work stops before writer quiescence
    And missing repositories are never initialized
    And archive traversal, duplicate paths, hardlinks, devices, symlink parents, and linked databases are rejected
    And no private contents, filenames, password values, or fingerprints are reported
    And wrong passwords and corrupted synthetic databases fail negative controls
    And missing Restic causes the full acceptance runner to fail without final PASS markers
