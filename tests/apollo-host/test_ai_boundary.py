from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def _source():
    return (ROOT / "modules/hosts/apollo/default.nix").read_text()


def test_apollo_serving_pins_the_dsx_runtime():
    source = _source()
    for argument in (
        '"apollo-dsx"',
        '"sha256:c57e24782ab02bad202dd033c08d9318d643f0ec631840b181bcc040bf985e42"',
        '"--model"\n            "/model/${apolloAiPack}"',
        '"--rank"\n            "/model/${apolloAiRankFile}"',
        '"--ctx"\n            "262144"',
        '"--arena-gb"\n            "150"',
        '"--cache-sessions"\n            "3"',
        '"--session-cache-gb"\n            "16"',
        '"--port"\n            "11542"',
    ):
        assert argument in source, argument


def test_apollo_serving_preserves_container_and_preflight_boundaries():
    source = _source()
    for boundary in (
        '"--user"\n            "1000:100"',
        '"--cpus=8"',
        '"--security-opt=no-new-privileges"',
        '"--ipc=host"',
        '"memlock=-1:-1"',
        '"nvidia.com/gpu=all"',
        '"${apolloAiModelDir}:/model:ro"',
        'chain_rules=$(iptables -S apollo-qwen-litellm)',
        '-A apollo-qwen-litellm -j REJECT --reject-with icmp-port-unreachable',
        '"${apolloAiPreflight}"',
        '"${apolloAiClean}"',
    ):
        assert boundary in source, boundary


def test_apollo_serving_keeps_only_the_serving_port():
    source = _source()
    assert "-m multiport --dports 11542 -j ACCEPT" in source
    assert "--dport 11560" not in source
    assert "--dports 11542,11560" not in source


def test_apollo_serving_dropped_the_vllm_stack():
    source = _source()
    for removed in (
        "serve-vllm.sh",
        "serve-lmcache.sh",
        "serve-pqnld.sh",
        "lmcache server",
        "pqnld-rs",
        "VLLM_SERVER_DEV_MODE",
        "apolloAiRuntime",
    ):
        assert removed not in source, removed
