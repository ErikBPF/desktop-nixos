"""The container-health probe reports live Docker health per container.

cAdvisor's health series is stale on the deployed Alloy, so the alert rule reads
this textfile metric instead. The probe must distinguish healthy, unhealthy and
no-healthcheck containers, and must survive containers without compose labels.
"""

import os
import pathlib
import stat
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
PROBE = ROOT / "modules/hosts/discovery/_container-health-probe.sh"

STUB = """#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  ps)
    printf 'plex\\nha-harness\\nplain\\n'
    ;;
  inspect)
    format="$3"
    name="$4"
    case "$format" in
      *compose.project*)
        case "$name" in
          plex) printf 'plex' ;;
          *) printf '' ;;
        esac
        ;;
      *State.Health*)
        case "$name" in
          plex) printf 'healthy' ;;
          ha-harness) printf 'unhealthy' ;;
          *) printf 'none' ;;
        esac
        ;;
      *) printf 'unexpected format: %s\\n' "$format" >&2; exit 2 ;;
    esac
    ;;
  *) printf 'unexpected docker args: %s\\n' "$*" >&2; exit 2 ;;
esac
"""


class ContainerHealthProbeTest(unittest.TestCase):
    def run_probe(self, directory):
        stub_dir = pathlib.Path(directory) / "bin"
        stub_dir.mkdir()
        stub = stub_dir / "docker"
        stub.write_text(STUB)
        stub.chmod(stub.stat().st_mode | stat.S_IXUSR)

        metrics = pathlib.Path(directory) / "metrics"
        metrics.mkdir()
        environment = dict(os.environ)
        environment["PATH"] = f"{stub_dir}:{environment['PATH']}"
        subprocess.run(
            ["bash", str(PROBE), str(metrics), "discovery"],
            check=True,
            capture_output=True,
            text=True,
            env=environment,
        )
        return (metrics / "container-health.prom").read_text().splitlines()

    def test_reports_each_state_with_labels(self):
        with tempfile.TemporaryDirectory() as directory:
            lines = self.run_probe(directory)
        self.assertEqual(
            lines,
            [
                'container_health_unhealthy{host="discovery",name="plex",project="plex"} 0',
                'container_health_unhealthy{host="discovery",name="ha-harness",project="none"} 1',
                'container_health_unhealthy{host="discovery",name="plain",project="none"} 0',
            ],
        )

    def test_unreachable_runtime_keeps_the_last_sample(self):
        with tempfile.TemporaryDirectory() as directory:
            metrics = pathlib.Path(directory) / "metrics"
            metrics.mkdir()
            output = metrics / "container-health.prom"
            output.write_text('container_health_unhealthy{host="discovery",name="old"} 0\n')

            stub_dir = pathlib.Path(directory) / "bin"
            stub_dir.mkdir()
            stub = stub_dir / "docker"
            stub.write_text("#!/usr/bin/env bash\nexit 1\n")
            stub.chmod(stub.stat().st_mode | stat.S_IXUSR)

            environment = dict(os.environ)
            environment["PATH"] = f"{stub_dir}:{environment['PATH']}"
            result = subprocess.run(
                ["bash", str(PROBE), str(metrics), "discovery"],
                capture_output=True,
                text=True,
                env=environment,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("name=\"old\"", output.read_text())


if __name__ == "__main__":
    unittest.main()
