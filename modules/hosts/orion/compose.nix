_: {
  flake.modules.nixos.orion-compose = _: {
    homelab.compose.stacks = [
      "shared" # homelab-net + alloy + scrutiny-collector
      "ai-models" # llama-server (AMD Vulkan GPU)
      "hermes-agent" # hermes agent
    ];
  };
}
