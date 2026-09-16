"""Self-check for toolcall-leak-guard. Run: python3 selftest.py"""

from __future__ import annotations

import importlib.util
import os

_HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("tlg", os.path.join(_HERE, "__init__.py"))
_tlg = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_tlg)
clean_response = _tlg.clean_response

LEAK_ONLY = (
    'invoke name="bash">\n'
    "date && ping -c1 discovery && tailscale status\n"
    "</invoke>"
)
PROSE_AND_LEAK = (
    "Verdict: repeat. Same kernel OOM as the 14:02 firing.\n\n"
    "<invoke name=\"bash\">free -m</invoke>"
)
CLEAN = "Verdict: new. Likely cause: disk fill on /var. Entry point: just switch-kepler."


def demo() -> None:
    assert clean_response(LEAK_ONLY) == "NO_REPLY"
    assert clean_response("<tool_call>{\"name\":\"terminal\"}</tool_call>") == "NO_REPLY"
    assert clean_response("```tool_call\n{\"cmd\": \"ls\"}\n```") == "NO_REPLY"
    assert clean_response('to=functions.exec_command {"cmd":"ls"}') == "NO_REPLY"
    assert clean_response(PROSE_AND_LEAK) == "Verdict: repeat. Same kernel OOM as the 14:02 firing."
    assert clean_response(CLEAN) is None
    assert clean_response("") is None
    print("toolcall-leak-guard selftest: OK")


if __name__ == "__main__":
    demo()
