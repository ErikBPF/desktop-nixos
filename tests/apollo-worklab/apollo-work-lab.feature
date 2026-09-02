@contract @unautomated
Feature: Apollo native work lab and host control plane
  Apollo is the single persistent development host, projects own their
  toolchains, and its Kubernetes cluster is a disposable execution plane.

  Background:
    Given Endeavour is an authorized administration client
    And Apollo is enrolled in the private network

  Scenario: Resume one persistent work session
    Given the named work session is running on Apollo
    When Endeavour disconnects and reconnects to Apollo
    Then the same editor, shell, and supported agent processes are visible
    And no nested terminal multiplexer is required

  Scenario: Let each project select its toolchain
    Given a project declares its supported development environment
    When the operator enters that project environment on Apollo
    Then the project language and build commands are available
    And Apollo does not select their versions through host language modules

  Scenario: Keep frequent control tools immediately available
    When the operator logs in to Apollo
    Then Kubernetes, Nix, host, storage, and network control commands are available
    And "stern" and "nvd" are available without changing the system generation
    But rare kernel diagnostics do not require permanent host packages

  Scenario: Diagnose the complete work lab without exposing secrets
    When the operator runs the Apollo work-lab diagnosis
    Then it reports host capacity and failed critical units
    And it reports Herdr, Syncthing, Orion cache, and five-node cluster health
    And it does not print credentials, private keys, tokens, or kubeconfig data

  Scenario: Use the canonical Orion cache path
    Given Orion's Nix cache is healthy on the private network
    When Apollo requests "http://orion:5000/nix-cache-info"
    Then the request succeeds without waiting for fallback

  Scenario: Keep the Kubernetes API on the admin boundary
    When an authorized administration client connects to "apollo:6443"
    Then the Kubernetes API is reachable
    But an ordinary tailnet peer cannot connect to "apollo:6443"

  Scenario: Administer the host noninteractively
    Given Endeavour authenticated to Apollo with an authorized public key
    When the operator invokes sudo
    Then sudo does not prompt for a password
    And default coding-agent aliases do not bypass approval or sandbox controls

  Scenario: Use the cluster without replacing existing contexts
    Given Apollo already has Kubernetes contexts
    When the Apollo development kubeconfig is installed
    Then the Apollo context is named "apollo-dev"
    And every previously active context remains available
    And the kubeconfig is mode "0600" and excluded from synchronization

  Scenario: Observe host disappearance and cluster degradation
    Given Apollo is an always-on host with five expected Kubernetes nodes
    When Apollo telemetry vanishes or fewer than five nodes remain ready
    Then existing fleet monitoring reports the affected Apollo condition
    And stale node-readiness evidence is treated as degradation
    And a failed MicroVM systemd unit uses the shared systemd failure alert

  Scenario: Exercise one disposable project workload
    Given a project explicitly selects the "apollo-dev" context
    When it creates a unique namespace and deploys a bounded workload
    Then the operator can inspect its events and logs
    And the operator can use an exec or ephemeral debug path
    And deleting the namespace removes every resource owned by that smoke run

  Scenario: Keep one writer for synchronized work
    Given project folders have converged on Apollo
    When Apollo becomes the remote-primary work host
    Then Apollo is the only active writer for those synchronized folders
    And Gemini is no longer a synchronization peer for those folders
    And Endeavour retains a receive-only versioned mirror

  Scenario: Refuse a seed that would fill temporary storage
    Given Apollo still uses the 240 GB system RAID1 for work folders
    When the selected folders cannot be seeded while leaving 20 percent free
    Then the writer remains unchanged
    And the cutover waits for a smaller folder set or the workload SSDs

  Scenario: Keep mutable agent and cluster credentials local
    When project folders synchronize between Apollo and Endeavour
    Then Codex, Claude Code, and OpenCode mutable state is not synchronized
    And credentials and kubeconfig are not copied as project data

  Scenario: Rebuild the disposable cluster safely
    Given repositories and work sessions live on the Apollo host
    And no cluster workload is the only copy of durable data
    When every Apollo Kubernetes MicroVM is rebuilt
    Then the cluster returns with five ready nodes
    And host repositories and work-session state remain intact

  Scenario: Retain Gemini without retaining its primary role
    Given Apollo has passed live cutover acceptance
    When Gemini remains running on Orion
    Then Gemini remains reachable as a rollback or utility container
    But Gemini does not automatically run the primary Syncthing, Herdr, or k3s duties
