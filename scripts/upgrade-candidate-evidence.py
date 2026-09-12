"""Record checked lock identities without copying potentially sensitive metadata."""

from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile


baseline, backup = sys.argv[1:]
receipt = {
    "baseline_revision": baseline,
    "before_lock_sha256": hashlib.sha256(Path(backup).read_bytes()).hexdigest(),
    "candidate_lock_sha256": hashlib.sha256(Path("flake.lock").read_bytes()).hexdigest(),
    "checked_at": datetime.now(timezone.utc).isoformat(),
    "validation": "dry-all",
}
destination = Path(subprocess.check_output(
    ["git", "rev-parse", "--git-path", "upgrade-candidate.json"], text=True
).strip())
with tempfile.NamedTemporaryFile(
    mode="w", dir=destination.parent, prefix="upgrade-candidate-", suffix=".tmp",
    delete=False,
) as output:
    temporary = Path(output.name)
    try:
        json.dump(receipt, output)
        output.write("\n")
        output.close()
        temporary.replace(destination)
    finally:
        temporary.unlink(missing_ok=True)
