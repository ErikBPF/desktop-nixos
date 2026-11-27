#!/usr/bin/env python3
"""Stdlib self-check for the alert-dedupe plugin. No Hermes import, no network."""
from __future__ import annotations

import asyncio
import importlib.util
import json
import os
import pathlib
import sys
import tempfile
import types

HERE = pathlib.Path(__file__).resolve().parent
PLUGIN = HERE / "__init__.py"

FIRING = """[Grafana] 🔴 warning · **orion**
orion: systemd unit nix-cache-builder.service is failed — check `systemctl status nix-cache-builder.service` / `journalctl -u nix-cache-builder.service` on the host · since 2026-10-26 09:09 UTC

[Response guide / owners](https://github.com/ErikBPF/homelab-gitops/blob/main/docs/alerting.md) · [Rule](https://grafana.homelab.pastelariadev.com/alerting/grafana/host-systemd-unit-failed/view?orgId=1)"""

REPEAT = FIRING.replace("2026-10-26 09:09", "2026-10-26 09:09")

NEW_EPISODE = FIRING.replace("2026-10-26 09:09", "2026-10-27 01:00")

RESOLVED = """[Grafana] 🟢 warning · **orion**
Previous condition: orion: systemd unit nix-cache-builder.service is failed — check `systemctl status nix-cache-builder.service` / `journalctl -u nix-cache-builder.service` on the host · since 2026-10-26 09:09 UTC · ended 2026-10-26 11:00 UTC

[Response guide / owners](https://github.com/ErikBPF/homelab-gitops/blob/main/docs/alerting.md) · [Rule](https://grafana.homelab.pastelariadev.com/alerting/grafana/host-systemd-unit-failed/view?orgId=1)"""

GROUPED = """[Grafana] 🔴 warning · **discovery**
discovery: systemd unit homelab-iac-drift.service is failed — check `systemctl status homelab-iac-drift.service` · since 2026-10-26 09:09 UTC
🔴 warning · **orion**
orion: nix-cache-builder.service build timed out · since 2026-10-26 09:09 UTC

[Rule](https://grafana.homelab.pastelariadev.com/alerting/grafana/host-systemd-unit-failed/view?orgId=1)"""

NO_RULE = """[Grafana] 🔴 critical · **kepler**
Authentik offsite source is missing · since 2026-10-26 09:09 UTC"""


def load_plugin():
    spec = importlib.util.spec_from_file_location("alert_dedupe", PLUGIN)
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules["alert_dedupe"] = mod
    spec.loader.exec_module(mod)
    return mod


def with_ledger(fn):
    with tempfile.TemporaryDirectory() as tmp:
        os.environ["ALERT_DEDUPE_LEDGER"] = str(pathlib.Path(tmp) / "ledger.json")
        os.environ["ALERT_DEDUPE_MODE"] = "annotate"
        try:
            return fn()
        finally:
            os.environ.pop("ALERT_DEDUPE_LEDGER", None)
            os.environ.pop("ALERT_DEDUPE_MODE", None)


def test_parse_firing():
    mod = load_plugin()
    inst = mod.parse_instances(FIRING)
    assert len(inst) == 1, inst
    i = inst[0]
    assert i.severity == "warning", i
    assert i.host == "orion", i
    assert i.rule == "host-systemd-unit-failed", i
    assert i.unit == "nix-cache-builder.service", i
    assert i.since == "2026-10-26 09:09 UTC", i
    assert i.resolved is False


def test_parse_grouped_and_missing_rule():
    mod = load_plugin()
    inst = mod.parse_instances(GROUPED)
    assert len(inst) == 2, inst
    assert {i.host for i in inst} == {"discovery", "orion"}
    assert mod.parse_instances(NO_RULE) == []


def test_first_firing_is_new_then_repeat():
    def run():
        mod = load_plugin()
        ledger = mod.Ledger.load()
        v1 = mod.classify(FIRING, ledger, thread_id="111")
        assert v1.kind == "new", v1
        assert mod.marker(v1) is None
        ledger.commit(v1, thread_id="111")

        v2 = mod.classify(REPEAT, ledger, thread_id="222")
        assert v2.kind == "repeat", v2
        assert v2.count == 2, v2
        assert mod.marker(v2).startswith("repeat #2"), mod.marker(v2)
        ledger.commit(v2, thread_id="222")

        v3 = mod.classify(NEW_EPISODE, ledger, thread_id="333")
        assert v3.kind == "new_episode", v3
        assert "new episode #2" in mod.marker(v3), mod.marker(v3)
        assert "222" in (mod.prior_thread(v3) or ""), mod.prior_thread(v3)
    with_ledger(run)


def test_resolved_closes_episode():
    def run():
        mod = load_plugin()
        ledger = mod.Ledger.load()
        ledger.commit(mod.classify(FIRING, ledger, thread_id="111"), thread_id="111")
        v = mod.classify(RESOLVED, ledger, thread_id="111")
        assert v.kind == "resolved", v
        ledger.commit(v, thread_id="111")
        after = mod.classify(REPEAT, ledger, thread_id="222")
        assert after.kind == "new", after
    with_ledger(run)


def test_missing_and_corrupt_ledger_degrade_to_unknown():
    def run():
        mod = load_plugin()
        p = pathlib.Path(os.environ["ALERT_DEDUPE_LEDGER"])
        p.write_text("{not json")
        ledger = mod.Ledger.load()
        v = mod.classify(FIRING, ledger, thread_id="1")
        assert v.kind == "unknown", v
        assert "cannot be confirmed" in mod.input_note(v, None)
    with_ledger(run)


def test_hooks_annotate_once_and_fail_open():
    def run():
        mod = load_plugin()
        assert mod.pre_llm_call(session_id="s1", turn_id="t1", user_message=FIRING,
                                platform="discord") in (None, "")
        first = mod.transform_llm_output(response_text="body", session_id="s1",
                                         turn_id="t1")
        assert first in (None, "body"), first
        note = mod.pre_llm_call(session_id="s2", turn_id="t2", user_message=REPEAT,
                                platform="discord")
        assert note and "repeat #2" in note, note
        out = mod.transform_llm_output(response_text="body", session_id="s2",
                                       turn_id="t2")
        assert out.startswith("repeat #2"), out
        # same turn is idempotent
        again = mod.transform_llm_output(response_text=out, session_id="s2",
                                         turn_id="t2")
        assert again in (None, out), again
        # non-alert text untouched
        assert mod.pre_llm_call(session_id="s3", turn_id="t3",
                                user_message="hello", platform="discord") is None
        # mode off
        os.environ["ALERT_DEDUPE_MODE"] = "off"
        try:
            assert mod.pre_llm_call(session_id="s4", turn_id="t4",
                                    user_message=REPEAT, platform="discord") is None
        finally:
            os.environ["ALERT_DEDUPE_MODE"] = "annotate"
    with_ledger(run)


class _FakeMessage:
    def __init__(self, content):
        self.content = content
        self.channel = types.SimpleNamespace(id="1521191614846865568")


def _adapter_classes():
    class FakeThread:
        def __init__(self, tid, parent_id):
            self.id = str(tid)
            self.parent_id = str(parent_id)
            self.archived = False
            self.name = f"thread-{tid}"

    class FakeClient:
        def __init__(self):
            self.threads = {}

        def get_channel(self, cid):
            return self.threads.get(cid)

        async def fetch_channel(self, cid):
            return self.threads.get(cid)

    class FakeAdapter:
        created = []

        def __init__(self, client):
            self._client = client

        async def _auto_create_thread(self, message):
            tid = 900 + len(self.created) + 1
            self.created.append(tid)
            thread = FakeThread(tid, message.channel.id)
            self._client.threads[int(tid)] = thread
            return thread

    return FakeAdapter, FakeClient


def with_fake_adapter(fn):
    adapter, client = _adapter_classes()
    fake = types.ModuleType("plugins.platforms.discord.adapter")
    fake.DiscordAdapter = adapter
    names = ("plugins", "plugins.platforms", "plugins.platforms.discord",
             "plugins.platforms.discord.adapter")
    saved = {name: sys.modules.get(name) for name in names}
    for name in names[:-1]:
        mod = types.ModuleType(name)
        mod.__path__ = []
        sys.modules[name] = mod
    sys.modules[names[-1]] = fake
    try:
        return fn(adapter, client)
    finally:
        for name, previous in saved.items():
            if previous is None:
                sys.modules.pop(name, None)
            else:
                sys.modules[name] = previous


def test_thread_reuse_same_fingerprint_and_changed_fingerprint():
    def run(Adapter, Client):
        mod = load_plugin()
        assert mod.install_thread_reuse(), "thread reuse hook not installed"
        adapter = Adapter(Client())
        first = asyncio.run(adapter._auto_create_thread(_FakeMessage(FIRING)))
        assert len(Adapter.created) == 1, Adapter.created
        ledger = mod.Ledger.load()
        ledger.commit(mod.classify(FIRING, ledger, thread_id=first.id), thread_id=first.id)

        repeat = asyncio.run(adapter._auto_create_thread(_FakeMessage(REPEAT)))
        assert repeat.id == first.id, (repeat.id, first.id)
        assert len(Adapter.created) == 1, Adapter.created

        changed = FIRING.replace("**orion**", "**kepler**")
        other = asyncio.run(adapter._auto_create_thread(_FakeMessage(changed)))
        assert other.id != first.id, (other.id, first.id)
        assert len(Adapter.created) == 2, Adapter.created
    with_fake_adapter(lambda adapter, client: with_ledger(lambda: run(adapter, client)))


def test_archived_thread_is_not_reused():
    def run(Adapter, Client):
        mod = load_plugin()
        assert mod.install_thread_reuse(), "thread reuse hook not installed"
        adapter = Adapter(Client())
        first = asyncio.run(adapter._auto_create_thread(_FakeMessage(FIRING)))
        ledger = mod.Ledger.load()
        ledger.commit(mod.classify(FIRING, ledger, thread_id=first.id), thread_id=first.id)
        first.archived = True

        second = asyncio.run(adapter._auto_create_thread(_FakeMessage(REPEAT)))
        assert second.id != first.id, (second.id, first.id)
        assert len(Adapter.created) == 2, Adapter.created
    with_fake_adapter(lambda adapter, client: with_ledger(lambda: run(adapter, client)))


def test_delayed_repeat_uses_matched_episode_thread():
    def run(Adapter, Client):
        mod = load_plugin()
        assert mod.install_thread_reuse(), "thread reuse hook not installed"
        adapter = Adapter(Client())
        older = asyncio.run(adapter._auto_create_thread(_FakeMessage(FIRING)))
        ledger = mod.Ledger.load()
        ledger.commit(mod.classify(FIRING, ledger, thread_id=older.id), thread_id=older.id)

        newer = asyncio.run(adapter._auto_create_thread(_FakeMessage(NEW_EPISODE)))
        assert newer.id != older.id, (newer.id, older.id)
        ledger = mod.Ledger.load()
        ledger.commit(mod.classify(NEW_EPISODE, ledger, thread_id=newer.id), thread_id=newer.id)

        delayed = asyncio.run(adapter._auto_create_thread(_FakeMessage(REPEAT)))
        assert delayed.id == older.id, (delayed.id, older.id)
        assert len(Adapter.created) == 2, Adapter.created
    with_fake_adapter(lambda adapter, client: with_ledger(lambda: run(adapter, client)))


def test_no_network_or_subprocess_imports():
    src = PLUGIN.read_text()
    for banned in ("import subprocess", "import socket", "urllib.request", "requests."):
        assert banned not in src, banned


def main():
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for fn in tests:
        fn()
    print("PASS alert-dedupe-selftest")


if __name__ == "__main__":
    try:
        main()
    except AssertionError as exc:
        print(f"FAIL alert-dedupe-selftest: {exc}", file=sys.stderr)
        raise
