# Selected personal repositories; Documents entry paths remain stable for
# umbrella sessions and the existing Syncthing working-file share.
{lib, ...}: let
  repos = [
    "homelab"
    "desktop-nixos"
    "homelab-iac"
    "cognee-homelab"
    "ndc"
    "LMCache"
    "agent-evals"
    "servarr"
    "homelab-gitops"
    "renovate-config"
    "hermes-flake"
    "hermes-skills"
    "code/home-assistant-config"
    "klipper-biqu"
    "kindle-dash"
    "opencode-flake"
    "codex-flake"
    "buzz-flake"
    "deepseek-harness-flake"
    "ha-agent"
    "cosmo-notes"
  ];
  target = repo: "/home/erik/Documents/erik/${repo}";
in {
  configurations.nixos.orion.module = {
    fileSystems = lib.genAttrs (map target repos) (path: {
      device = "/projects/workspaces/erik/${lib.removePrefix "/home/erik/Documents/erik/" path}";
      fsType = "none";
      options = ["bind" "x-systemd.requires-mounts-for=/projects"];
    });
    systemd.services.syncthing.unitConfig.RequiresMountsFor = map target repos;
  };
}
