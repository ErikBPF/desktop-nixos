# Declarative OpenCode (v2)

**Status:** v2 default on all `home.opencode` hosts in source; Endeavour
activation pending the FlakeHub publish of the packaged v2 binary. The
filename is historical: per-profile launchers no longer exist.

`modules/dev/opencode.nix` owns the shared Home Manager configuration,
provider policy and workflow commands. It imports
`opencode-flake`'s `homeManagerModules.withPackageV2`, which installs the
packaged **OpenCode v2** binary as the default `opencode` command
(`packages/opencode-v2` in `opencode-flake`, official Linux x64 npm release,
auto-patchelf only). Home and work use one configuration with default model
**DeepSeek V4.1 Flash** (`litellm/deepseek-v4.1-flash`, via OpenCode Go); the
`work` provider and its models remain selectable in the same config.

## What changed from v1

- The v1 profile launchers (`opencode-home`, `opencode-work`, `*-omo`) and the
  late `OPENCODE_CONFIG_DIR` overlays are gone. v2 reads the same
  `~/.config/opencode/opencode.json`, so one config serves every directory.
- `ol`/`ow` are the only shortcuts: they run `opencode <directory>` for the
  homelab and dataplatform checkouts. No per-project serve backends.
- Plugins use the v2 API (`plugins`, `file://` entries, `setup(ctx)`):
  - `modules/dev/opencode-plugins-v2/rtk` — rewrites shell commands through a
    shim after OpenCode authorises the original (rtk-ai/rtk#4197).
  - `modules/dev/opencode-plugins-v2/gateway-headers` — stamps
    `x-opencode-session` on `litellm`/`work` model requests.
  - `@filecrop/opencode-ponytail-v2@0.1.0` — hash-pinned response-style adapter.
  The v1 `@tarquinen/opencode-dcp` plugin and the v1 `ponytail.mjs`/`rtk.ts`
  adapters do not run under v2 and were dropped.

## Shared state caveat

v1 and v2 both use `~/.config/opencode/` and `~/.local/share/opencode/`.
Retiring v1 hands v2 the existing session database; back it up before the
first v2 run on a host (the previous isolated trial at
`~/.local/share/opencode-v2/` never touched it).

## Verification

- `nix flake check` in `opencode-flake` builds `packages.opencode-v2` and
  checks its `--version`.
- `tests/opencode-profiles/` runs the v2 plugin unit test (`test_headers.mjs`),
  the live loopback header test (`test_header_integration.py`), and the sops
  credential-wiring contract (`test_credentials.py`) against the installed
  binary.
- Activation and verification are recorded per host; a source change does not
  deploy Orion, Apollo or Pathfinder until their next Home Manager run.
