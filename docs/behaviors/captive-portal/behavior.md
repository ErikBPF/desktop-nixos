# Captive portal login

**Status:** Accepted behavior; activated on Endeavour, real hotspot validation pending.

Human seed (verbatim):

> lets explore how to make our wifi config open hotspot login whem prompted

Accepted correction (verbatim):

> open login window once per connection

Endeavour opens one Brave window when NetworkManager detects a captive portal on an activated Wi-Fi connection. Repeated checks, temporary connectivity changes and listener restarts must not open another window for that activation. Reconnecting permits a new window, including reconnecting to the same saved network. Ordinary online, offline, wired and VPN connections do not launch it. Detection also works when login starts with an already-connected captive network.

The change owns Endeavour's NetworkManager probe, a Home Manager graphical-session service, its listener and behavioral tests. Deployment was subsequently authorized by the user’s “apply” instruction. Existing firewall, VPN and DNS policy remains unchanged.

Observed regression (verbatim):

> entering on a wifi with capitiv portal opened https://nmcheck.gnome.org/check_network_status.txt

The user confirmed the page displayed “NetworkManager is online”. Login navigation must remain HTTP through the probe and any HTTP portal redirect. The login window uses a separate runtime browser profile so automatic HTTPS upgrades can be disabled there without changing the normal Brave profile. Explicit HTTPS destinations still use TLS and normal certificate validation.
