"""Check effective host options without building or activating either host.

Run: python3 -m unittest discover -s tests/gpu-exchange
"""
import json
from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[2]
OPTIONS = """hosts: builtins.mapAttrs (_: host: let c = host.config; in {
  drivers = c.services.xserver.videoDrivers;
  initrdModules = c.boot.initrd.kernelModules;
  kernelModules = c.boot.kernelModules;
  extraModules = map (p: p.pname or p.name) c.boot.extraModulePackages;
  toolkit = c.hardware.nvidia-container-toolkit.enable;
  persistence = c.hardware.nvidia.nvidiaPersistenced;
  clocks = c.systemd.services.nvidia-conservative-clocks.script or "";
  clockDependencies = c.systemd.services.nvidia-conservative-clocks.requires or [];
  packages = map (p: p.pname or p.name) c.environment.systemPackages;
  graphics = c.hardware.graphics.enable;
  graphics32Bit = c.hardware.graphics.enable32Bit;
  autoUpgrade = c.system.autoUpgrade.enable;
  stacks = c.homelab.compose.stacks;
}) { inherit (hosts) kepler apollo; }"""


class GPUExchangeOptions(unittest.TestCase):
    def test_effective_driver_exchange_and_fault_limits(self):
        hosts = json.loads(subprocess.check_output(
            ["nix", "eval", "--json", ".#nixosConfigurations", "--apply", OPTIONS],
            cwd=ROOT, text=True,
        ))
        kepler, apollo = hosts["kepler"], hosts["apollo"]
        with self.subTest(host="kepler"):
            self.assertEqual(kepler["drivers"], ["amdgpu"])
            self.assertIn("amdgpu", kepler["initrdModules"])
            self.assertIn("amdgpu", kepler["kernelModules"])
            self.assertFalse(any("nvidia" in value for key in
                                 ("initrdModules", "kernelModules", "extraModules", "packages")
                                 for value in kepler[key]))
            self.assertFalse(kepler["toolkit"])
            self.assertFalse(kepler["persistence"])
            self.assertEqual(kepler["clocks"], "")
            self.assertFalse(kepler["autoUpgrade"])
            self.assertFalse({"whisper-gpu", "qwen4b-gpu", "retrieval"} & set(kepler["stacks"]))
        with self.subTest(host="apollo"):
            self.assertEqual(apollo["drivers"], ["nvidia"])
            self.assertIn("nvidia", apollo["initrdModules"])
            self.assertTrue({"nvidia", "nvidia_modeset", "nvidia_uvm", "nvidia_drm"}
                            <= set(apollo["kernelModules"]))
            self.assertTrue(any("nvidia" in module for module in apollo["extraModules"]))
            self.assertTrue(apollo["toolkit"])
            self.assertTrue(apollo["persistence"])
            self.assertTrue(apollo["graphics"])
            self.assertTrue(apollo["graphics32Bit"])
            self.assertIn("nvtop", " ".join(apollo["packages"]))
            self.assertIn("nvidia-persistenced.service", apollo["clockDependencies"])
            self.assertIn("--power-limit=170", apollo["clocks"])
            self.assertIn("--lock-gpu-clocks=210,1500", apollo["clocks"])


if __name__ == "__main__":
    unittest.main()
