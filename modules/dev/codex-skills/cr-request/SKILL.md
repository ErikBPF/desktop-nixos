---
name: cr-request
description: Ask hackerman-cr to review or re-review a pull request now from this workstation. Use for /cr-request, $cr-request, "review this PR with hackerman", "request a hackerman review", "re-review this PR", or when a published head needs a fresh verdict. Replaces the GitHub comment command the bot does not support.
---

# Request a hackerman-cr review

hackerman-cr has no comment trigger and no inbound webhook. It reviews every new
head on a timer. This skill is the local replacement for a comment command: it
requeues one head on `discovery`, runs the collector, and waits for the
published marker.

## Run

From `~/Documents/erik/desktop-nixos`:

    just pr-review-request <owner>/<repo> <pr>

Examples:

    just pr-review-request ErikBPF/aster 42
    just pr-review-request ErikBPF/desktop-nixos 511

The command reads the live head with your own `gh` auth. It never uses the bot
credential.

## Read the result

- `published <url>` — the review comment and gate check are live. Open the URL.
- `ALREADY queued|leased|reusing` — a review is already in flight for that head;
  wait for the timer or rerun later.
- `NO-REVIEW` — the collector has not seen that head yet. The command triggers
  the collector, which queues it as a normal new head.
- Timeout after 20 minutes — not a verdict. Inspect the queue:

    sudo sqlite3 /home/erik/homelab/apps/hermes-daedalus/review-ledger/ledger.db \
      "select state, count(*) from reviews group by state;"

    systemctl list-units 'hermes-pr-review-trigger*'
    journalctl -u 'hermes-pr-review-trigger*' --since '-15 min'

## Boundaries

- Automatic review already covers every new head. Use this only for a head with
  no review, or when you want a fresh verdict at the same commit.
- A published head is requeued on purpose: its old publication marker is
  cleared, the next review runs the model again, and it updates the existing bot
  comment in place. The printed URL is this run's result.
- Do not run the ledger or publish scripts directly. `hermes-pr-review-request`
  is the supported entry point and keeps the ledger root-owned.
- Never paste a token. The command needs none.
- The review is P1/P2 only. An empty finding list approves the head; it does not
  replace human review of design or intent.
