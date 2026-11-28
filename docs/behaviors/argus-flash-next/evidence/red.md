# Assertion-failing RED

**Status:** Observed 2026-11-28, before implementation.

`pytest -q tests/orion-flash-next/test_config.py`: three assertion failures:

- Orion did not import `m.nixos.orion-strata-flash-next`.
- Flash Next had no declarative module owner.
- Discovery still named its probe `strata-chat-health-probe`.

The file was subsequently renamed to `test_flash_next.py` because collecting it together with the existing monitoring suite's `test_config.py` caused a Python module-name collision. That collection error was infrastructure, not another RED or a runtime failure.

## RV readiness regression

The official `serve/server.py` health handler returns HTTP 200 and `status: ok` while reporting model readiness separately through `loaded`. Executing the shipped probe with fixtures reproduced a false healthy gauge for an unloaded model.

`pytest -q tests/orion-flash-next/test_health_probe.py` observed **7 assertion failures and 3 passing cases** before the fix. Each failure compared an incorrectly published `1` against expected `0`; there were no collection or infrastructure errors. Cases cover an unloaded model, wrong service, missing readiness, nonboolean readiness, arrays, malformed JSON, and a failed HTTP request with a success-shaped body. After semantic JSON validation, all 10 cases pass. Fixtures execute the actual shell check with a local curl substitute; they issue no network or inference requests.
