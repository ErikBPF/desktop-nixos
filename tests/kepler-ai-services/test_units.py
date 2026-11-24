import pathlib


ROOT = pathlib.Path(__file__).resolve().parents[2]
HOST = ROOT / "modules/hosts/kepler"


def test_kepler_registers_both_ai_services():
    host = (HOST / "default.nix").read_text()
    assert "m.nixos.kepler-parakeet" in host
    assert "m.nixos.kepler-whisper" in host


def test_parakeet_unit_shape():
    unit = (HOST / "kepler-parakeet.nix").read_text()
    assert "flake.modules.nixos.kepler-parakeet" in unit
    assert "--port 9001" in unit
    assert "PARAKEET_DEVICE = \"Vulkan0\"" in unit
    assert "RequiresMountsFor = \"/fast/ai-models\"" in unit
    assert "StateDirectory = \"parakeet\"" in unit
    assert "Restart = \"always\"" in unit


def test_whisper_unit_shape():
    unit = (HOST / "kepler-whisper.nix").read_text()
    assert "flake.modules.nixos.kepler-whisper" in unit
    assert "vulkanSupport = true" in unit
    assert "--port 9000" in unit
    assert "-l pt" in unit
    assert "--inference-path /v1/audio/transcriptions" in unit
    assert "RequiresMountsFor = \"/fast/ai-models\"" in unit
    assert "StateDirectory = \"whisper\"" in unit


def test_both_units_share_the_vram_budget_note():
    for name in ("kepler-parakeet.nix", "kepler-whisper.nix"):
        text = (HOST / name).read_text()
        assert "VRAM" in text, f"{name} must record the co-residency budget"
