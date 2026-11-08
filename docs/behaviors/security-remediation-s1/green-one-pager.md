# Publisher evidence: GREEN and independent review

**Stage / revision:** GREEN / 2. **Status:** local regression complete; deployment unobserved.
**Owner / date:** desktop-nixos / 2026-11-07. **Basis:** user requested “do s0 to s4”; coordination plan revision 2, E01.

Invalid evidence now rejects the entire review packet rather than dropping findings into an approval. The publisher emits a failed check, preserves the original packet in the stale archive and marks its ledger row failed. Valid empty reviews still approve; valid findings retain their normal review behavior. Tests use temporary bundles and fake GitHub methods; no real review was published.

The regression first failed against the original implementation. The expanded suite covers mixed valid/invalid, missing and unreadable evidence, valid packets and duplicate retries. Independent review identified a second path: an already-published row resisted the normal failed transition, retaining a reusable success marker. A new assertion reproduced that failure. The revision explicitly requeues that row, removes its published marker and finishes failed, preserving the ledger’s ordinary terminal-state rules.

`python3 tests/pr-review-publish.py`, `just lint` and `just fmt-check` passed. The allowed Discovery toplevel dry-run passed without building or deploying. The original mixed-packet failure, published-row RED and corrected GREEN belong to the coordination execution receipts. The independent reviewer rechecked the correction and found no further material issue.

This establishes local publisher behavior only. Q1 in the coordination record still governs a named Discovery rollout and live check. Recovery should disable publication through the owning configuration if necessary; restoring fail-open behavior is not an acceptable rollback. Existing user changes in the canonical checkout were preserved.
