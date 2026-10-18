"""Stdlib callback-boundary checks; not native dispatch or E2E. Run: python3 selftest.py."""

import importlib.util
import io
import logging
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch
import subprocess
import sys

spec = importlib.util.spec_from_file_location("rtk_plugin", Path(__file__).with_name("__init__.py"))
plugin = importlib.util.module_from_spec(spec)
spec.loader.exec_module(plugin)
hooks = {}
plugin.register(SimpleNamespace(register_hook=lambda name, callback: hooks.update({name: callback})))
hook = hooks["pre_tool_call"]


def demo(case="all"):
    checks = {
        "terminal": terminal,
        "unrelated": unrelated,
        "failure": failure,
        "logging": logging_check,
    }
    for name, check in checks.items():
        if case in ("all", name):
            check()
    if case == "all":
        print("rtk-rewrite selftest: OK")


def terminal():
    args = {"command": "git status", "timeout": 10}
    with patch.object(plugin, "_rewrite", return_value="rtk git status"):
        result = hook(tool_name="terminal", args=args)
    assert result == {"action": "modify", "args": {"command": "rtk git status"}}, "native modify directive missing"
    assert args["timeout"] == 10
    with patch.object(plugin, "_rewrite") as rewrite:
        for args in (None, {}, {"command": ""}, {"command": 1}, {"command": "  rtk git status"}):
            assert hook(tool_name="terminal", args=args) is None
        rewrite.assert_not_called()


def unrelated():
    with patch.object(plugin, "_rewrite", return_value="rtk git status") as rewrite:
        for name in ("", "execute_code", "other", "terminal_extra"):
            args = {"command": "git status"}
            assert hook(tool_name=name, args=args) is None, "unrelated tool rewritten"
            assert args == {"command": "git status"}
        rewrite.assert_not_called()


def failure():
    with patch.object(plugin.shutil, "which", return_value="/synthetic/rtk"):
        for error in (OSError("synthetic"), subprocess.TimeoutExpired("rtk", 2)):
            with patch.object(plugin.subprocess, "run", side_effect=error):
                assert hook(tool_name="terminal", args={"command": "git status"}) is None
        for code, output in ((1, "rtk git status"), (0, ""), (0, "git status")):
            with patch.object(plugin.subprocess, "run", return_value=SimpleNamespace(returncode=code, stdout=output)):
                assert plugin._rewrite("git status") is None, "failed rewrite accepted"
    with patch.object(plugin.shutil, "which", return_value=None), patch.object(plugin.subprocess, "run") as run:
        assert hook(tool_name="terminal", args={"command": "git status"}) is None
        run.assert_not_called()


def logging_check():
    stream = io.StringIO()
    handler = logging.StreamHandler(stream)
    old_level = plugin.logger.level
    plugin.logger.setLevel(logging.DEBUG)
    plugin.logger.addHandler(handler)
    try:
        original = "git status SYNTHETIC_CREDENTIAL_MARKER"
        rewritten = "rtk " + original
        with patch.object(plugin, "_rewrite", return_value=rewritten):
            hook(tool_name="terminal", args={"command": original})
        assert original not in stream.getvalue() and rewritten not in stream.getvalue()
        assert "SYNTHETIC_CREDENTIAL_MARKER" not in stream.getvalue(), "command leaked into logger"
    finally:
        plugin.logger.removeHandler(handler)
        plugin.logger.setLevel(old_level)


def native(root):
    """Run official framework dispatch in an isolated HERMES_HOME; never execute tools."""
    sys.path.insert(0, root)
    from hermes_cli import plugins
    from agent.tool_executor import _pre_tool_block
    manager = plugins.PluginManager()
    plugins._plugin_manager = manager
    directory = Path(__file__).resolve().parent
    manifest = plugins.parse_manifest_file(directory / "plugin.yaml", directory, "user", "")
    assert manifest is not None
    plugin.register(plugins.PluginContext(manifest, manager))
    ref = SimpleNamespace(name="terminal", args={"command": "git status", "timeout": 10},
                          task_id="synthetic", call_id="synthetic", trace=[])
    with patch.object(plugin, "_rewrite", return_value="rtk git status"):
        blocked, args = _pre_tool_block(SimpleNamespace(), ref)
    assert blocked is None
    assert args == {"command": "rtk git status", "timeout": 10}
    assert ref.args["command"] == "git status", "in-place mutation hid directive failure"
    ref.name = "other"
    with patch.object(plugin, "_rewrite") as rewrite:
        assert _pre_tool_block(SimpleNamespace(), ref) == (None, ref.args)
        rewrite.assert_not_called()
    print("rtk-rewrite native dispatch: OK (synthetic caller boundary, no tool execution)")


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--native":
        native(sys.argv[2])
    else:
        demo(sys.argv[1] if len(sys.argv) > 1 else "all")
