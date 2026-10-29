# Shared compiler-cache writers

**Status:** Accepted source behavior, 2026-10-29; deployment remains separate.

Human continuation, verbatim:

> continue

Question presented to the owner:

> Which remote hosts should be allowed to write Orion’s shared compiler cache? Source enables Endeavour; existing ACL tests also admit laptop and Kepler. I recommend preserving those known consumers while denying other remote writers, including Discovery’s broad hub grant.

Owner answer, verbatim:

> Endeavour, laptop and Kepler (recommended)

Native question identifier: `call_74b4203eead44b9cb9f9d6ee50b7a258`, item 0.

These three remote identities may mutate the shared cache. Other remote peers,
including Discovery, must not mutate it merely because they can reach its port.
Existing reads remain available. Local trusted maintenance remains possible.
Source behavior does not authorize deployment or a live tailnet probe.
