# Explicit OpenCode model approval

**Status:** Runtime regression and generation fix verified. Independent review found no issues. Required CI and supported head review remain pending.

## Human seed and outcome

> our opencode go model list should be showing only a small list of approved models and providers. Check why its not. Lets connect our codex and claude accounts also. Also hook on pi harnes

This follow-up repairs the model approval gap observed after [PR #563](https://github.com/ErikBPF/desktop-nixos/pull/563) was deployed. Account connections and other harness behavior remain outside this change. The [accepted manifest](../../../modules/dev/pi-harness/src/approved-models.json) is unchanged.

The deployed global OpenCode catalog still exposed three unapproved LiteLLM entries: `apollo-deepseek-v41-flash`, `qwen-chat`, and `qwen3.8-flash`. The earlier test exercised the built-in catalog without the complete managed explicit declarations, so it did not reproduce this case.

## Cause and change

OpenCode v2.2.1 applies explicit configured models after the local catalog transform. Its model editor creates missing model records when applying those declarations. Consequently, the plugin could remove a model and a later explicit declaration could recreate it.

The [Home Manager configuration](../../../modules/dev/opencode.nix) now filters explicit model declarations through the same shared manifest before generating OpenCode configuration. The existing plugin continues to filter the built-in catalog. Providers without explicit model declarations retain their original settings. Approved model metadata, authentication references, API routing, and Work reasoning constraints are preserved.

The three old definitions remain as source metadata because an existing context contract reads one of them. Their unapproved IDs are absent from generated OpenCode configuration. Other clients and their routes are unchanged.

## Evidence and limits

The new [runtime regression](../../../tests/opencode-profiles/test_model_allowlist.py) carries every managed provider declaration and the actual model approval plugin into an isolated native OpenCode process. It replaces credentials with synthetic values and endpoints with an unused loopback address. Before the fix, its exact-set assertion failed with precisely the three deployed extras. After the fix, all four model approval tests passed and the runtime returned exactly the 17 approved entries for OpenCode's four enabled providers.

An evaluated before/after comparison against merged base `beb0fdf48db6ab0d063cf146ac990fb5c68baa85` verifies that the only rendered provider difference is LiteLLM's explicit model set shrinking from nine to six. All retained provider and model values are identical. This is a configuration/runtime catalog check, not live subscription inference.

A fresh independent reviewer read the fix and connected code, reran all four approval tests, and found no issues. The full 22-test OpenCode profile suite, seven Work/default-model contracts, real native RTK tool roundtrip, lint, formatting, documentation links, and Endeavour dry build passed. The Work contract exposed an unnecessary `pkgs.lib` dependency in the first implementation; the final filter uses Nix builtins and preserves the contract's minimal module import. Existing deprecation and temporary-directory warnings remain. No account or live inference check was performed for this follow-up.

## Delivery and recovery

The user authorized the follow-up PR through `merge and deploy`. This work is isolated in `worktrees/opencode-explicit-allowlist-20261124`; prior feature, deployment, and dirty main checkouts are preserved. Required CI and supported head review remain gates. The parent deployment owner will activate the reviewed configuration and compare the actual global/backend catalogs with the manifest. Recovery is the previous Home Manager generation. No account, key, or gateway route is changed.
