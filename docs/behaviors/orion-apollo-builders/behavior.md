# Builder placement — human seed

**Status:** Human seed; acceptance refinement is recorded separately.

> do a /rv, check if anything else is needed and lets merge all to main

> lets make apollo and orion the builders. No strain on kepler, discovery or endeavour

Clarifications:

> local should be a fallback for when builders are not available

> we need to completely remove kace from endeavour

Confirmed selections:

> Host and guest removal

> Enroll server daemons

Continuation:

> continue. Kace is no longer active. It can be safely removed without backups or extra validations

Latest scope correction (supersedes guest removal):

> vm guest is the only machine that needs to keep kace. We can merge things to main and wait for next orion cache build

Earlier delivery constraint:

> build packages on orion and send to discovery. Orion is the official cache
