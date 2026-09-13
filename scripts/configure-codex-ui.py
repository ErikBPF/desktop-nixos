"""Set Codex display and planning defaults while preserving mutable settings."""

import os
from pathlib import Path
import sys
import tempfile

import tomlkit


def configure(path):
    doc = tomlkit.parse(path.read_text()) if path.exists() else tomlkit.document()
    items = ["five-hour-limit", "weekly-limit", "context-remaining", "model-with-reasoning"]
    if (doc.get("tui", {}).get("status_line") == items
            and doc.get("tui", {}).get("auto_recap") is False
            and doc.get("tools", {}).get("update_plan", {}).get("enabled") is True):
        return
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
