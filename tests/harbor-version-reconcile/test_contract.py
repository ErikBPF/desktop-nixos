import re
from pathlib import Path


ROOT = Path(__file__).parents[2]
HARBOR = ROOT / "modules/hosts/discovery/servarr-harbor"


def test_vendored_harbor_installer_and_schema_follow_the_declared_version():
    setup = (HARBOR / "scripts/harbor-setup.sh").read_text()
    template = (HARBOR / "config/harbor/harbor.yml.tmpl").read_text()

    version = re.search(r'HARBOR_VERSION="\$\{HARBOR_VERSION:-v([^}]+)\}"', setup)
    schema = re.search(r"^_version: (.+)$", template, re.MULTILINE)

    assert version and schema
    assert schema.group(1) == version.group(1)
    assert 'VERSION_DIR="$INSTALLER_DIR/$HARBOR_VERSION"' in setup
    assert 'HARBOR_DIR="$VERSION_DIR/harbor"' in setup


def test_vendored_harbor_source_pins_the_leaf_revision():
    module = (ROOT / "modules/hosts/discovery/harbor.nix").read_text()
    assert "8ff0cb0d20f5806e873268b425deeac113cfa04e" in module
