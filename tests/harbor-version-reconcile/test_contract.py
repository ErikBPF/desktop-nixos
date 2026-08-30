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
    current = '$SUDO ln -sfn "$HARBOR_DIR" "$INSTALLER_DIR/current"'
    assert current in setup
    assert setup.index(current) > setup.index("$SUDO docker compose up -d")


def test_vendored_harbor_source_pins_the_leaf_revision():
    module = (ROOT / "modules/hosts/discovery/harbor.nix").read_text()
    assert "504cbd1b1f1582e8feafe1c6c0208c207df49488" in module


def test_restore_recipes_follow_the_active_installer_link():
    justfile = (ROOT / "justfile").read_text()
    assert justfile.count(".harbor-installer/current") == 2
    assert ".harbor-installer/harbor/" not in justfile
