from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
GEMINI = (ROOT / "modules/hosts/orion/gemini.nix").read_text()
JUSTFILE = (ROOT / "justfile").read_text()


def test_gemini_runs_a_single_node_k3s_server():
    assert "services.k3s = {" in GEMINI
    assert "enable = true;" in GEMINI
    assert 'role = "server";' in GEMINI
    assert '"--node-name=${ctName}"' in GEMINI
    assert '"--node-ip=${ctIp}"' in GEMINI
    assert '"--tls-san=${ctName}"' in GEMINI
    assert 'disable = ["traefik"];' in GEMINI
    assert "allowedTCPPorts = [2222 6443 22000];" in GEMINI


def test_orion_supplies_k3s_container_kernel_prerequisites():
    assert 'boot.kernelModules = ["br_netfilter" "overlay"];' in GEMINI
    assert '"net.bridge.bridge-nf-call-iptables" = 1;' in GEMINI
    assert '"net.bridge.bridge-nf-call-ip6tables" = 1;' in GEMINI
    assert '"net.ipv4.ip_forward" = 1;' in GEMINI


def test_gemini_checks_host_kernel_defaults_instead_of_writing_proc_sys():
    assert '"--kubelet-arg=protect-kernel-defaults=true"' in GEMINI
    assert '"KubeletInUserNamespace"' not in GEMINI
    assert '"kernel.panic" = 10;' in GEMINI
    assert '"kernel.panic_on_oops" = 1;' in GEMINI
    assert '"vm.overcommit_memory" = 1;' in GEMINI
    assert 'additionalCapabilities = ["CAP_SYSLOG"];' in GEMINI
    assert 'node = "/dev/kmsg";' in GEMINI
    assert 'modifier = "r";' in GEMINI
    assert 'hostPath = "/dev/kmsg";' in GEMINI
    assert "isReadOnly = true;" in GEMINI


def test_pastelariadev_kubeconfig_is_merged_without_clobbering_homelab():
    recipe = JUSTFILE.split("kubeconfig-pastelariadev:", 1)[1].split("\n\n", 1)[0]

    assert "ssh gemini" in recipe
    assert "https://gemini:6443" in recipe
    assert "sed 's/: default$/: pastelariadev-gemini/'" in recipe
    assert "kubectl config rename-context pastelariadev-gemini pastelariadev" in recipe
    assert "kubectl config delete-context pastelariadev" in recipe
    assert 'KUBECONFIG="$base:$cluster" kubectl config view --raw --flatten' in recipe
    assert 'kubectl config use-context "$active"' in recipe
    assert "kubectl --context pastelariadev get nodes" in recipe


def test_pastelariadev_has_a_read_only_remote_health_check():
    recipe = JUSTFILE.split("diagnose-pastelariadev:", 1)[1].split("\n\n", 1)[0]

    assert "ssh gemini" in recipe
    assert "systemctl is-active k3s" in recipe
    assert "k3s kubectl get nodes -o wide" in recipe
    assert "ss -ltnp 'sport = :6443'" in recipe
    assert "journalctl -u k3s -b --no-pager -n 80" in recipe


def test_gemini_contains_no_declarative_workloads():
    assert "services.k3s.manifests" not in GEMINI
    assert "services.k3s.autoDeployCharts" not in GEMINI
