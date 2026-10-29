# Graphify package and wheel updates

**Status:** Local package, native operations, workspace and four-host dry checks pass; hosted validation pending.

Graphify 0.9.53 and its MCP extra use the 58-wheel dependency set from the
previously passing x86_64-linux/Python 3.14 package. The checked-in
[`graphify-lock.json`](../../modules/dev/graphify-lock.json) records each exact
public PyPI artifact URL and SHA256. Nix fetches and verifies each artifact;
the installation runs offline from that wheel directory. New releases on the
index cannot alter these inputs. The initial lock preserves the prior bytes,
including Pydantic 2.14.1 and pydantic-core 2.50.1.

Previously, a fixed-output derivation ran an online dependency resolver during
the build. Publishing Pydantic 2.14.2 changed the resolved wheel set and failed
the aggregate hash check. Updating that aggregate hash would repeat the same
failure on the next transitive release. Artifact-level locking removes the
resolution step from builds while preserving integrity checks.

For an intentional update, enter the declared development shell and run
`just update-graphify <version>`. The updater resolves the explicit release
with the same Python/platform tags, using only the public PyPI index in a
clean environment. It converts pip's dry-run report to the lock, rejecting
unhashed, yanked, duplicate or non-public wheel inputs. Review the complete
dependency diff before committing. A Python minor-version change needs a
deliberate updater/platform adjustment; the package refuses a mismatched lock.
The [pip install documentation](https://pip.pypa.io/en/stable/cli/pip_install/)
and [installation report schema](https://pip.pypa.io/en/stable/reference/installation-report/)
describe the dry-run resolution interface.

Native wheels also require Nix runtime linkage. The package applies `autoPatchelfHook`
with the C++ and zlib runtimes, then checks NumPy, RapidFuzz and tree-sitter
operations plus the Graphify CLI during installation. Previously, even the
passing cached package failed native imports in a clean environment.

Check and Security workflows accept PRs targeting dependency branches as well
as main; their push triggers remain main-only. Security explicitly requests PR
read access and disables action comments, with no write permission. Existing
public desktop secret checks passed before this capability declaration; no
desktop API-denial incident is claimed.

Run `python3 -m unittest discover -s tests/graphify-lock -v`, the package build,
the existing local-workspace suite, and the owner lint/format/documentation and
Endeavour, Pathfinder, Orion and Apollo dry-build gates. An update does not activate a host. Roll back a bad
dependency update by reverting its lock change; keep the lock-based build path.
Artifact integrity does not establish that upstream packages are vulnerability-free.

The accepted behavior remains in
[`behavior.md`](../behaviors/graphify-wheel-lock/behavior.md). Private coordination
receipts retain the initial assertion RED and dependency-provenance evidence.
