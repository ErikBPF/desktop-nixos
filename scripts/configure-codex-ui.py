"""Set Codex defaults and retire the old Headroom route, preserving other settings."""

import os
from pathlib import Path
import sys
import tempfile

import tomlkit


def configure(path):
    doc = tomlkit.parse(path.read_text()) if path.exists() else tomlkit.document()
    retire_headroom = doc.get("openai_base_url") == "http://127.0.0.1:8788/v1"
    items = ["five-hour-limit", "weekly-limit", "context-remaining", "model-with-reasoning"]
    if (not retire_headroom
            and doc.get("tui", {}).get("status_line") == items
            and doc.get("tui", {}).get("auto_recap") is False
            and doc.get("tools", {}).get("update_plan", {}).get("enabled") is True):
        return
    if retire_headroom:
        # Codex 0.154 uses auth-dependent OpenAI defaults when this is absent;
        # OPENAI_BASE_URL belongs to Hermes and does not select Codex's provider.
        del doc["openai_base_url"]
    if "tui" not in doc:
        doc["tui"] = tomlkit.table()
    doc["tui"]["status_line"] = items
    doc["tui"]["auto_recap"] = False
    doc.setdefault("tools", tomlkit.table()).setdefault("update_plan", tomlkit.table())["enabled"] = True
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as out:
        temporary = Path(out.name)
        try:
            out.write(tomlkit.dumps(doc))
            out.flush()
            os.replace(temporary, path)
        finally:
            temporary.unlink(missing_ok=True)


if __name__ == "__main__":
    configure(Path(sys.argv[1]))
