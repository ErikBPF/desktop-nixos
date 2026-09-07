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
  bootEntries = c.boot.loader.systemd-boot.configurationLimit;
  stacks = c.homelab.compose.stacks;
  kernelVersion = c.boot.kernelPackages.kernel.version;
  kernelImage = "${c.boot.kernelPackages.kernel}/${c.system.boot.loader.kernelFile}";
  guestKernels = builtins.mapAttrs (_: vm: let g = vm.config.config; in {
    version = g.boot.kernelPackages.kernel.version;
    image = "${g.boot.kernelPackages.kernel}/${g.system.boot.loader.kernelFile}";
    hypervisorImage = "${g.microvm.kernel.dev}/vmlinux";
  }) c.microvm.vms;
}) { inherit (hosts) kepler apollo; }"""


class GPUExchangeOptions(unittest.TestCase):
    def test_effective_driver_exchange_and_fault_limits(self):
        hosts = json.loads(subprocess.check_output(
            ["nix", "eval", "--json", ".#nixosConfigurations", "--apply", OPTIONS],
            cwd=ROOT, text=True,
        ))
        kepler, apollo = hosts["kepler"], hosts["apollo"]
        for name, host in hosts.items():
            with self.subTest(kernel=name):
                self.assertEqual(host["kernelVersion"], "7.2.3")
                self.assertEqual(host["kernelImage"], "/nix/store/4f2m1k8c5ih0fa6zh8762k4s6pa6bw0p-linux-7.2.3/bzImage")
            with self.subTest(guest_kernels=name):
                expected = {
                    "version": "7.2.3",
                    "image": "/nix/store/4f2m1k8c5ih0fa6zh8762k4s6pa6bw0p-linux-7.2.3/bzImage",
                    "hypervisorImage": "/nix/store/5pfk37ynwny49qfmb7s0sy57d8jqvih3-linux-7.2.3-dev/vmlinux",
                } if name == "kepler" else {
                    "version": "6.18.49",
                    "image": "/nix/store/s40h0m3746r0l287laa9sxa9345bkykf-linux-6.18.49/bzImage",
                    "hypervisorImage": "/nix/store/8gsy6nldplfw12ylblabahhay8bv8xfx-linux-6.18.49-dev/vmlinux",
                }
                self.assertTrue(host["guestKernels"])
                for kernel in host["guestKernels"].values():
                    self.assertEqual(kernel, expected)
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
            self.assertIsNone(apollo["bootEntries"])
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
