# Official Orion Flash Next runtime

**Status:** Accepted behavior from the 2026-11-28 session.

Human seed, verbatim:

> lets use our argus cleytin credentials to check for open alerts on grafana and discord. Lets archive all older and duped ones first them explore fixes

Accepted steering, verbatim:

> rebooting it. monitor

> strata flash netxt is the official one. strata-chat is stale

> update on desktop-nixos

The human answered **Update the desktop-nixos configuration** when asked whether to change its configuration to make `strata-flash-next` official and retire stale `strata-chat`.

Desktop declares the existing official runtime, retaining its pinned image, saved profile, GPU access, memory-lock limit, mounts, tailnet bind, parallelism, and logprob settings. Orion no longer starts the retired `ai-models` Compose stack, and the operator rollout inventory no longer requires it. Discovery identifies the official runtime in its health probe while preserving existing Grafana metric names and the verified `/health` response contract.

This change authorizes source configuration work. No deployment, inference request, credential rotation, or unrelated incident repair is part of this slice.
