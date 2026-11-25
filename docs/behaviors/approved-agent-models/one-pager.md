# Approved agent models and subscription accounts

**Status:** Review repairs verified. Activation, browser authentication, and gateway rollout remain pending. Artifact revision 2.

## Human seed

> our opencode go model list should be showing only a small list of approved models and providers. Check why its not. Lets connect our codex and claude accounts also. Also hook on pi harnes

Accepted clarification:

> les use deepseek v.1 flash and glm5.3 not the flash. For providers, lets add everything from opencode via litellm, directly and codex models. Lets see if it is possible to serve our codex models via litellm

The user selected both interactive `pi` and durable `pi-harness` for account connections. The optional question about the entire Go catalog remains unanswered. The recorded default is the smaller shortlist: DeepSeek V4.1 Flash and full GLM 5.3, plus the four existing Codex aliases. Existing Work routes remain available.

## Outcome and cause

OpenCode v2.2.1 merges the built-in catalog with configured models. Explicit model entries do not limit that catalog. The legacy configuration normalizer drops `whitelist` and `blacklist`. Provider policies restrict providers but have no model action. This explains the unexpected OpenAI and Go entries.

The [native catalog plugin](../../../modules/dev/opencode-plugins-v2/model-allowlist/index.js) removes models outside the [shared manifest](../../../modules/dev/pi-harness/src/approved-models.json), including future unknown models. It preserves approved runtimes and authentication. The manifest feeds OpenCode filtering, Pi cycling, and the durable catalog. Pi's `enabledModels` controls startup and cycling; it does not restrict the full interactive picker.

## Changes and boundaries

Home routes use full GLM 5.3 with its actual pricing. Work retains its existing GLM Flash route. Pi receives the selected gateway aliases and direct Go credential reference. The durable harness reuses native Codex and Anthropic providers. The pinned coding-agent dependency supplies public `ModelRuntime` and the same persistent authentication store and lock as interactive Pi. This avoids copying refresh tokens between clients or implementing new refresh logic.

OpenCode already has stored OpenAI OAuth. Its installed Anthropic integration advertises only API-key and environment methods, so native Claude subscription sign-in is not implemented there. Separate Pi browser sign-ins are pending. No credential values belong in this artifact or Git.

## Evidence and limits

The real-catalog test failed before filtering and passed afterward. Alias parity failed before missing Pi aliases were added and passed afterward. The [runtime regression checks](../../../tests/opencode-profiles/test_model_allowlist.py) verify that Astra's Responses override preserves LiteLLM's endpoint after actual v2 normalization. Targeted Python checks passed: 31 tests and 81 subtests, with one existing readiness-retry resource warning. The durable TypeScript build and 30 tests passed. Lint, formatting, documentation links, and the Endeavour toplevel dry build passed. Orion built package `/nix/store/bbs2ni6yjkh78q9c8l8hdhqgkc0p64s4-pi-harness-0.1.0` and check `/nix/store/fwv85b38mm02pz8qln5c7vcvgxskwrwy-pi-harness-tests-0.1.0`.

Independent review fixed three verified defects: mixed legacy/native provider configuration erased LiteLLM settings; the initial shared-auth implementation exposed unapproved built-in catalogs; and retired saved GLM Flash sessions failed on their next request. The final adapter exposes exactly five providers and 20 approved chat models, with no image or classifier catalog, while delegating authentication to the official locked store. Retired sessions now report explicit `--model litellm/glm-5.3` recovery. An additional Pi Go provider-ID correction uses `opencode-go`.

The bounded independent rereview verified all three repairs. Synthetic streaming checks preserved full authentication results and the native LiteLLM, Codex, Claude, and Go endpoints, including Go's session header. These are offline protocol checks, not live account verification.

LiteLLM advertises four Codex aliases and its server OAuth store is present and unexpired. Astra's first HTTP 400 was an input-shape error; a corrected request still failed upstream. Luna Chat returned HTTP 502. Both the local Sops Go key and the separately saved Go key returned HTTP 401. No successful live subscription inference is claimed. Separate IaC and Servarr worktrees prepare full GLM 5.3 registration, bounded personal-key access, and session-header forwarding. They are prepared for linked draft PRs and remain undeployed.

## Continuing work and recovery

The built Home Manager candidate would remove the currently deployed, unrelated `secretspec-export.service`. Activation is therefore pending identification of the deployed configuration's owning checkout. The main checkout is older than its deployed Pi setup; all task edits are isolated from existing work. Complete Pi browser authentication, replace the invalid Go credential through the sanctioned secret store, and obtain scope-appropriate gateway rollout authorization. Recovery uses the previous Home Manager generation and bounded gateway grant revocation. No account was deleted or key reminted.

The final candidate built as `/nix/store/5fv9sa3hcch27b3w0ppd2ll6qfjpnhlp-home-manager-generation`; it was not activated. The installed generation remains `/nix/store/0s9l84g0j8naff31g5n9vl8i0kyahmjp-home-manager-generation`. The packaged harness status smoke passed with no live tasks or model usage. Final account inspection still found no saved Pi providers.

Pending questions are bound to checkout `worktrees/approved-agent-models-20261124`, artifact revision 2: Q1 confirms whether to expand the Go catalog, with the two-model default recorded above; Q2 requests completion or status of Pi browser sign-ins; Q3 requests the checkout that owns the deployed Home Manager configuration. Q2 blocks account verification. Q3 blocks activation. No tuicr session is active. First-draft receipts are preserved in `~/.local/state/codex/approved-agent-models-20261124/`.

## Delivery

The user requested `create pr` after reviewing the implementation report. This authorizes commits, branch publication, and linked draft PRs for Desktop, IaC, and Servarr. It does not authorize activation, applying infrastructure changes, merging, or restarting LiteLLM. Ship the Servarr forwarding prerequisite and IaC route before the Desktop consumer. Live authentication and deployed-source ownership remain unresolved.
