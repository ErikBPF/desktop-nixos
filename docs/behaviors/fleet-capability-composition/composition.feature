# Status: Proposed, unautomated contract. No step bindings or RED/GREEN claim.
# Plan and evidence: ../../proposals/2026-09-08-fleet-capability-composition.md
# Source baseline: 85401f6916304f0d87dd8cb1bba987bd9fd6c227
@fleet_composition
Feature: Compose shared fleet capabilities without changing host behavior
  Operators can select a shared capability while retaining each host's
  network ownership, hardware exceptions, access and recovery behavior.

  @W1
  Scenario Outline: Selected wired hosts retain magic-packet wake
    Given "<host>" explicitly selects the shared wake capability
    And its recorded permanent MAC is "<mac>"
    When its system configuration is evaluated
    Then its wake policy is magic-packet only
    And its network owner remains "<manager>"
    And its physical NIC remains "<nic>"
    And its DHCP, addresses, bridge membership and NAT remain unchanged

    Examples:
      | host      | mac               | manager        | nic    |
      | apollo    | 2a:38:4d:07:de:54 | networkd       | lan0   |
      | kepler    | 74:56:3c:47:d1:77 | networkd       | enp5s0 |
      | orion     | b4:2e:99:92:4f:8b | NetworkManager | enp4s0 |
      | discovery | 64:51:06:1a:f8:1a | scripted       | eno1   |

  @W2
  Scenario: Discovery retains the physical NIC recovery workarounds
    Given Discovery bridges eno1 into br0
    When its shared wake capability is evaluated
    Then wake policy applies to eno1 rather than br0
    And the existing NIC rule remains the effective first match
    And its naming policy remains unchanged
    And TCP, TCP6 and generic segmentation offload remain disabled

  @W3
  Scenario: Unselected hosts do not acquire a hardware capability
    Given the Pi, cloud guests and roaming hosts do not select shared wake
    When all deployed host configurations are evaluated
    Then none receives wake policy from the new capability
    And a server role alone does not select the capability
    And an absent permanent MAC is allowed for an unselected host

  @W4
  Scenario Outline: Incomplete wake selection fails before deployment
    Given a host selects the shared wake capability
    And "<required fact>" is absent
    When its system configuration is evaluated
    Then evaluation reports "<diagnostic>"
    And no activation is attempted

    Examples:
      | required fact                            | diagnostic                    |
      | the permanent MAC                        | wake requires a permanent MAC |
      | the existing link target on a non-NM host | wake requires a link target   |

  @C1
  Scenario: Repeated composition preserves effective behavior
    Given a host selects its shared capabilities
    When the same pinned configuration is evaluated again
    Then its effective policy is unchanged
    And its existing NIC rule remains the only applicable owned wake rule
    And no duplicate route flags or tool configuration are introduced

  @N1
  Scenario: Local clients retain route policy without changing the router
    Given Apollo, Kepler and Orion select the local-client capability
    When the fleet Tailscale configuration is evaluated
    Then those three hosts accept DNS and reject imported routes
    And Discovery retains its existing advertised /32 routes and router mode
    And other hosts retain their baseline route acceptance
    And enrollment tags, authentication paths and firewall exposure are unchanged

  @D1
  Scenario: Developer environments share composition without growing scope
    Given the desktop profile, Orion and Apollo select the shared CLI bundle
    When their Home Manager configurations are evaluated
    Then all seven common tools remain available at their baseline versions
    And host-specific tools, aliases and credential locations remain unchanged
    And hosts outside the bundle retain their baseline package sets

  @P1
  Scenario: Server profiles compose kernel policy without upgrading kernels
    Given every existing server-profile consumer keeps its current imports
    When the kernel policy is moved into a named capability
    Then the profile contains composition only
    And all host and guest kernel images retain their baseline identities
    And hardware overrides, boot limits and upgrade policies remain unchanged

  @P2
  Scenario: Cloud profiles compose platform behavior without broadening access
    Given Voyager, Telstar and Vanguard use the OCI profile
    When platform policy is moved into a named capability
    Then the profile contains composition only
    And SSH port 2222 remains restricted to the tailnet firewall interface
    And serial console, virtio drivers and removable EFI fallback are retained
    And per-host disks, ESP paths and architectures remain unchanged
