# Feedback reconciliation

## Bootstrap registration

Question: `call_011f0321931a4b07ba6ed34082993db1`.
User answer: “use iac to create voice credentials. register it and use”.
Checkout: desktop-nixos/worktrees/voice-dictation; related IaC voice-litellm worktree.
Disposition: completed through existing sanctioned bootstrap secret and IaC. The normal AppRole remains unable to edit its own policy. Saved policy plan preserved the live Cloudflare read permission and added only the two voice paths; foundation apply succeeded. KV apply then used the normal AppRole and succeeded. Runtime cache was fetched from OpenBao, compared privately, and installed mode0600. Empty handoff removed. No credential value exposed.

## Isolated artifact publication

Question: `call_105f5eade4e24be583c7cc86a24dfd9c`.
User answer: “Approve push and merge-commit exception”.
Prepared artifact: Servarr commit `f991f2cfe84bfd43f14aa47c147439704ebcfa79`, only voice Compose/source-entrypoint/docs.
Disposition: branch pushed; PR363 opened. First CI failed because its branch-tip comparison included old unrelated drift. Main was merged into the PR branch, preserving the exact artifact as an ancestor; repeated publication is within the authorized rollout. Validation and secret-scan CI passed; PR363 merged. The temporary IaC-managed merge-commit setting was restored to squash-only and verified. Exact artifact pin and Orion deployment completed. Deploy pin stays f991f2c, not the integration branch tip. No review TUI session was requested.

## Model recovery

Direct bounded inference also timed out while health passed. One owner-managed restart of Orion's existing pinned ai-models stack completed. The model remains in loading state, with llama-server waiting in drm_syncobj_array_wait_timeout. No GPU reset, host reboot, second restart or shared configuration change was attempted. Independent CPU ASR deployment and observed local rewrite fallback continue within the accepted failure behavior.
