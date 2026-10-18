"""Self-check for toolcall-leak-guard. Run: python3 selftest.py"""

from __future__ import annotations

import importlib.util
import os
import sys
from types import SimpleNamespace

_HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("tlg", os.path.join(_HERE, "__init__.py"))
_tlg = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_tlg)
clean_response = _tlg.clean_response
hooks = {}
_tlg.register(SimpleNamespace(register_hook=lambda name, callback: hooks.update({name: callback})))
transform = hooks["transform_llm_output"]

STRUCTURED = {
    "raw_object_only": '{"tool_call":{"name":"terminal","arguments":{"command":"ls"}}}',
    "raw_python_only": "{'tool_call': {'name': 'terminal'}}",
    "raw_object_value": '{"tool_call":"to=functions.exec_command"}',
    "raw_python_value": "{'tool_call': 'to=functions.exec_command'}",
    "raw_object_quoted_xml": '{"tool_call":"<invoke>payload</invoke>"}',
    "nested_naked_xml": '<invoke><invoke>ls</invoke>"<tool_call>payload</tool_call>"</invoke>',
    "unterminated_naked_xml_attr": '<invoke name="terminal" arg="`SYNTHETIC`',
    "escaped_delimiters": '\\`<invoke name="terminal">SYNTHETIC</invoke>\\`',
}


def regression(case="all"):
    if case in ("all", "xml_truncated_boundary"):
        xml_truncated_boundary()
    if case in ("all", "xml_attribute_quotes"):
        xml_attribute_quotes()
    if case in ("all", "xml_markup_boundary"):
        xml_markup_boundary()
    if case in ("all", "markdown_brackets"):
        markdown_brackets()
    for name, text in STRUCTURED.items():
        if case not in ("all", name):
            continue
        result = transform(response_text=text)
        if name == "escaped_delimiters":
            assert result is not None and "<invoke" not in result.lower(), name
        else:
            assert result == "NO_REPLY", name
    evidence = '`<invoke name="terminal">quoted</invoke>`'
    if case in ("all", "raw_object_plus_evidence"):
        assert transform(response_text=evidence + "\n" + STRUCTURED["raw_object_only"]) == evidence, "raw_object_plus_evidence"
    if case != "all":
        return
    for text in STRUCTURED.values():
        if text == STRUCTURED["escaped_delimiters"]:
            continue
        for quoted in (f"`` {text} ``", f"```text\n{text}\n```", f"~~~text\n{text}\n~~~", "> " + text,
                       "'" + text.replace("\\", "\\\\").replace("'", "\\'") + "'",
                       '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'):
            assert transform(response_text=quoted) is None, "whole evidence changed"
            assert transform(response_text=quoted + "\n" + STRUCTURED["raw_object_only"]) == quoted, "mixed whole evidence changed"
    for ordinary in ('{"note":"tool_call","name":"terminal"}', "{'ordinary': 'value'}", "tool_call is a field name"):
        assert transform(response_text=ordinary) is None, "ordinary prose/object false positive"
    for text in ('{"TOOL_CALL": {"name": "terminal"}}', "{'tool_call': {'name': 'terminal'", '<INVOKE arg="`SYNTHETIC`',
                 "don't " + STRUCTURED["raw_object_only"], '\\"' + STRUCTURED["raw_object_only"]):
        result = transform(response_text=text)
        assert result is not None and not _tlg._LEAK_SNIFF.search(result), "syntax quotation exemption"


def xml_truncated_boundary():
    evidence = '[`<invoke>SYNTHETIC</invoke>`](https://example.invalid)'
    unfinished = (
        '<invoke>"<tool_call>SYNTHETIC</tool_call>"',
        '<invoke>\n"<tool_call>SYNTHETIC</tool_call>"',
        '<invoke arg="unfinished\n\'<tool_call>SYNTHETIC</tool_call>\'',
        '<invoke arg=\'unfinished\n"<tool_call>SYNTHETIC</tool_call>"',
    )
    complete = '<invoke>\n"<tool_call>SYNTHETIC</tool_call>"\n</invoke>'
    assert transform(response_text=complete) == "NO_REPLY", "complete multiline XML survived"
    assert transform(response_text=complete + "\n" + evidence) == evidence, "evidence after complete XML changed"
    for text in unfinished:
        assert transform(response_text=text) == "NO_REPLY", "unfinished raw XML must own EOF"
        assert transform(response_text=text + "\n" + evidence) == "NO_REPLY", "evidence inside unfinished XML exempted"
        assert transform(response_text=evidence + "\n" + text) == evidence, "evidence before unfinished XML changed"
        assert transform(response_text="Verdict\n" + text) == "Verdict", "prose before unfinished XML changed"
        for quoted in (f"`` {text} ``", f"```xml\n{text}\n```", f"~~~xml\n{text}\n~~~",
                       "> " + text.replace("\n", "\n> "),
                       "'" + text.replace("\\", "\\\\").replace("'", "\\'") + "'",
                       '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'):
            assert transform(response_text=quoted) is None, "wholly quoted unfinished XML changed"
            assert transform(response_text=quoted + "\n" + text) == quoted, "prefix whole evidence changed"
    assert transform(response_text='<not-a-tool unfinished\n"<tool_call>SYNTHETIC</tool_call>"') is None, "ordinary incomplete tag became tool root"


def xml_attribute_quotes():
    from xml.etree import ElementTree
    evidence = '[`<invoke>SYNTHETIC</invoke>`](https://example.invalid)'
    for quote in ("'", '"'):
        for count in (1, 2, 3, 4):
            slashes = "\\" * count
            text = (f'<invoke><payload arg={quote}{slashes}{quote}>SYNTHETIC</payload>'
                    f'{quote}<invoke>SYNTHETIC</invoke>{quote}'
                    f'<tool_call>SYNTHETIC</tool_call>{quote}</invoke>')
            ElementTree.fromstring(text)
            assert transform(response_text=text) == "NO_REPLY", "XML backslash attribute payload survived"
            assert transform(response_text=evidence + "\n" + text) == evidence, "XML attribute displaced evidence"
            assert transform(response_text="Verdict\n" + text) == "Verdict", "XML attribute removed prose"
            for quoted in (f"`` {text} ``", f"```xml\n{text}\n```", f"~~~xml\n{text}\n~~~", "> " + text,
                           "'" + text.replace("\\", "\\\\").replace("'", "\\'") + "'",
                           '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'):
                assert transform(response_text=quoted) is None, "whole XML attribute evidence changed"
                assert transform(response_text=quoted + "\n" + text) == quoted, "mixed XML attribute evidence changed"


def xml_markup_boundary():
    from xml.etree import ElementTree
    closed = (
        '<invoke><!-- </invoke> -->"<tool_call>SYNTHETIC</tool_call>"</invoke>',
        '<invoke><![CDATA[</invoke>]]>"<tool_call>SYNTHETIC</tool_call>"</invoke>',
        '<invoke><?x </invoke> ?>"<tool_call>SYNTHETIC</tool_call>"</invoke>',
    )
    # Literal '<' is invalid in XML attributes, but raw dumps still fail closed.
    attributes = (
        '<invoke arg="</invoke>">"<tool_call>SYNTHETIC</tool_call>"</invoke>',
        '<invoke><payload arg="</invoke>">SYNTHETIC</payload>"<tool_call>SYNTHETIC</tool_call>"</invoke>',
    )
    evidence = '[`<invoke>SYNTHETIC</invoke>`](https://example.invalid)'
    for text in closed + attributes:
        if text in closed:
            ElementTree.fromstring(text)
        result = transform(response_text=text)
        assert result is not None and not _tlg._LEAK_SNIFF.search(result), "XML markup exposed payload tool marker"
        assert result == "NO_REPLY", "XML markup exposed payload remnants"
        assert transform(response_text="Verdict\n" + text) == "Verdict", "XML markup removed prose"
        assert transform(response_text=evidence + "\n" + text) == evidence, "XML markup displaced evidence"
        for quoted in (f"`` {text} ``", f"```xml\n{text}\n```", f"~~~xml\n{text}\n~~~", "> " + text,
                       "'" + text + "'", '"' + text.replace('"', '\\"') + '"'):
            assert transform(response_text=quoted) is None, "whole XML markup evidence changed"
            assert transform(response_text=quoted + "\n" + text) == quoted, "mixed XML markup evidence changed"
    for text in tuple(text[:-9] for text in closed) + (
                 '<invoke><!-- </invoke>\n"<tool_call>SYNTHETIC</tool_call>"',
                 '<invoke><![CDATA[</invoke>\n"<tool_call>SYNTHETIC</tool_call>"',
                 '<invoke><?x </invoke>\n"<tool_call>SYNTHETIC</tool_call>"',
                 '<invoke><!-- </invoke>\n -->"<tool_call>SYNTHETIC</tool_call>"',
                 '<invoke><![CDATA[</invoke>\n]]>"<tool_call>SYNTHETIC</tool_call>"',
                 '<invoke><?x </invoke>\n ?>"<tool_call>SYNTHETIC</tool_call>"'):
        assert transform(response_text=text) == "NO_REPLY", "unclosed XML markup exempted payload quotes"


def markdown_brackets():
    evidence = '[`<invoke>SYNTHETIC</invoke>`](https://example.invalid)'
    controls = (evidence, '[`` {"tool_call":{"name":"terminal"}} ``](https://example.invalid)',
                "['{\"tool_call\":{\"name\":\"terminal\"}}']", '[ordinary brackets]',
                '[`<invoke>SYNTHETIC</invoke>`]')
    for text in controls:
        assert transform(response_text=text) is None, "Markdown bracket evidence changed"
        assert transform(response_text=text + "\n" + STRUCTURED["raw_object_only"]) == text, "mixed bracket evidence changed"
    for text in ('[{"tool_call":{"name":"terminal"}}]', "[{'tool_call': {'name': 'terminal'}}]",
                 '[{"ordinary": [{"tool_call":"to=functions.exec_command"}]}]',
                 '[{"tool_call":{"name":"terminal"}'):
        assert transform(response_text=text) == "NO_REPLY", "genuine tool-call list survived"
        assert transform(response_text=evidence + "\n" + text) == evidence, "tool list displaced legitimate evidence"


def native(root):
    """Official registration and output finalizer; synthetic state, no gateway or API."""
    global transform
    from pathlib import Path
    sys.path.insert(0, root)
    from hermes_cli import plugins
    from agent.turn_finalizer import apply_llm_output_transform
    manager = plugins.PluginManager()
    plugins._plugin_manager = manager
    directory = Path(_HERE)
    manifest = plugins.parse_manifest_file(directory / "plugin.yaml", directory, "user", "")
    assert manifest is not None
    _tlg.register(plugins.PluginContext(manifest, manager))
    def native_transform(*, response_text):
        agent = SimpleNamespace(session_id="synthetic", model="synthetic", platform="")
        result, changed, original = apply_llm_output_transform(
            agent, response_text, turn_id="synthetic", logger=_tlg.logger)
        if not changed:
            assert result == response_text and original is None
            return None
        assert original == response_text
        return result
    transform = native_transform
    regression()
    print("toolcall-leak-guard native finalizer: OK (synthetic state, not gateway E2E)")

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
    assert clean_response("```tool_call\n{\"cmd\": \"ls\"}\n```") is None
    assert clean_response('to=functions.exec_command {"cmd":"ls"}') == "NO_REPLY"
    assert clean_response(PROSE_AND_LEAK) == "Verdict: repeat. Same kernel OOM as the 14:02 firing."
    assert clean_response(CLEAN) is None
    assert clean_response("") is None
    leak = '<invoke name="bash">ls</invoke>'
    quoted = (
        f"`{leak}`", f"``{leak}``", f"```xml\n{leak}\n```",
        f"~~~xml\n{leak}\n~~~", f"> {leak}\n> evidence",
        f"'{leak}'", '"<tool_call>payload</tool_call>"',
        f'"He said \\"{leak}\\"."',
    )
    for text in quoted:
        assert clean_response(text) is None, "closed evidence removed"
        assert _tlg._transform_llm_output(response_text=text) is None
        assert clean_response(text + "\n" + leak) == text, "mixed evidence lost"
        assert clean_response(leak + "\n" + text) == text
        assert clean_response("<invoke>truncated\n" + text) == "NO_REPLY", "Q-GUARD-TRUNC-BOUNDARY: unfinished raw XML owns EOF"
    for text in ("`" + leak, "```xml\n" + leak, "~~~xml\n" + leak,
                 "'" + leak, '"<tool_call>payload',
                 "don't " + leak, "agents' " + leak, '\\"' + leak):
        result = clean_response(text)
        assert result is not None and not _tlg._LEAK_SNIFF.search(result), "malformed quote exempted"
    for text in ("```xml\n'" + leak + "'", "~~~xml\n`" + leak + "`"):
        result = clean_response(text)
        assert result is not None and not _tlg._LEAK_SNIFF.search(result)
    assert clean_response("quoted " + leak) == "quoted"
    assert clean_response("Verdict\n<invoke>truncated") == "Verdict"
    hooks = {}
    _tlg.register(SimpleNamespace(register_hook=lambda name, callback: hooks.update({name: callback})))
    assert hooks["transform_llm_output"](response_text=quoted[0]) is None
    assert hooks["transform_llm_output"](response_text=quoted[0] + "\n" + leak) == quoted[0]
    assert clean_response('<invoke>echo "<tool_call>nested</tool_call>"</invoke>') == "NO_REPLY", "payload quotation exempted naked outer block"
    assert clean_response("Report " + quoted[0] + " verdict " + leak) == "Report " + quoted[0] + " verdict"
    # Exercise every existing positive through the registered outer hook too.
    for text in quoted:
        assert transform(response_text=text) is None
        assert transform(response_text=text + "\n" + leak) == text
    regression()
    print("toolcall-leak-guard selftest: OK")


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--native":
        native(sys.argv[2])
    elif len(sys.argv) > 1:
        regression(sys.argv[1])
    else:
        demo()
