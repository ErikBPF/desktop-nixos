{
  inputs = {
    # Retain both exact recovery sources and their own dependency locks.
    kepler-recovery-baseline.url = "github:ErikBPF/desktop-nixos/a3f290e015eacce61e718f8596cdb6acc3716c7c";
    kepler-recovery-guest.url = "github:ErikBPF/desktop-nixos/228bc67bf427fa1c4d33508f3f5967e2b1008d7a";

    # Pinned to the master revision whose qutebrowser entry no longer carries
    # the upstream-reverted insecure mark; nixos-unstable still lags it.
    # Restore github:nixos/nixpkgs/nixos-unstable once the channel advances.
    nixpkgs.url = "github:nixos/nixpkgs/5c3cda7610193a82ba555e178e80de6667ae03de";

    # Kepler imports this fixed revision because ZFS 2.4.4 supports kernels up
    # to 7.2 and the root input dropped that series. Apollo and the
    # `profile-server` hosts follow the root revision pin; endeavour and
    # pathfinder pin `linuxPackages_zen` themselves.
    # Revisit once ZFS supports 7.3: https://github.com/ErikBPF/desktop-nixos/issues/459
    nixpkgs-gpu-kernel.url = "github:nixos/nixpkgs/d3b13ad75cc492690728f9307e443dec9ef9a20e";

    # Kepler recovery tooling is reviewed against SecretSpec 0.13.0.
    nixpkgs-secretspec.url = "github:nixos/nixpkgs/e7a3ca8092b61ff85b6a45bf863ea2b2d6a661b3";

    # Pinned solely for orca-slicer: 2.3.2 fails GL init ("Unable to init glew
    # library, Missing GL version" -> empty build plate) on Mesa 26.x/Wayland.
    # 2.3.1 from this commit renders correctly. Drop once nixpkgs ships a fix.
    nixpkgs-orca.url = "github:nixos/nixpkgs/09061f748ee21f68a089cd5d91ec1859cd93d0be";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hyprland = {
      url = "git+https://github.com/hyprwm/Hyprland?submodules=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    jovian = {
      url = "github:Jovian-Experiments/Jovian-NixOS";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    quickshell = {
      url = "git+https://github.com/quickshell-mirror/quickshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-colors.url = "github:misterio77/nix-colors";

    stylix = {
      url = "github:nix-community/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix.url = "github:Mic92/sops-nix";
    claude-code-nix.url = "github:sadjow/claude-code-nix";

    # Marketplace + Open VSX mirror, so all VS Code extensions resolve
    # declaratively (incl. ones absent from nixpkgs' curated set).
    nix-vscode-extensions = {
      url = "github:nix-community/nix-vscode-extensions";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    import-tree.url = "github:vic/import-tree";

    # Remote deploy with magic rollback (auto-revert on lost reachability).
    # Subsequent switches only; first install stays nixos-anywhere/nixos-infect.
    # See modules/deploy-rs.nix and docs/proposals/2026-06-30-deploy-rs-as-deploy-standard.md.
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hermes-flake = {
      url = "https://flakehub.com/f/ErikBPF/hermes-flake/*";
      inputs.flake-parts.follows = "flake-parts";
      inputs.microvm.follows = "microvm";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    codex-flake = {
      url = "https://flakehub.com/f/ErikBPF/codex-flake/*";
      inputs.flake-parts.follows = "flake-parts";
      inputs.home-manager.follows = "home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    buzz-flake = {
      url = "github:ErikBPF/buzz-flake";
      inputs.flake-parts.follows = "flake-parts";
      inputs.home-manager.follows = "home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    deepseek-harness-flake = {
      url = "github:ErikBPF/deepseek-harness-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Held at 0.1.60: 0.1.62 (opencode 2.3.0) fails the native shell roundtrip
    # test with `bash: nomatch: invalid option name`. Pin the exact version:
    # `/*` re-resolves to the newest release on every `nix flake update`.
    # Revisit trigger: issue #490 — lift the hold once a release passes
    # tests/local-workspace-sessions/test_tool_roundtrip.py.
    opencode-flake = {
      url = "https://flakehub.com/f/ErikBPF/opencode-flake/=0.1.60";
      inputs.flake-parts.follows = "flake-parts";
      inputs.home-manager.follows = "home-manager";
      # Match the published flake's toolchain; newer Bun changes dependency hashes.
      inputs.nixpkgs.url = "github:nixos/nixpkgs/3ed67ec0a4d3c7ab4ae1f04f8ee8df07bfa506a2";
    };

    opencode-tui = {
      url = "github:ErikBPF/opencode-tui";
      inputs.flake-parts.follows = "flake-parts";
      inputs.home-manager.follows = "home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ponytail = {
      url = "github:DietrichGebert/ponytail";
      flake = false;
    };

    # Runtime jobs execute this reviewed source revision, never a mutable checkout.
    homelab-iac = {
      url = "github:ErikBPF/homelab-iac/7c5d785420c794769cb2c4952fb9916e99788450";
      flake = false;
    };

    # Terminal multiplexer for AI coding agents (claude-code/codex/opencode/
    # hermes). Third-party Rust flake — pinned to a release tag, and left on
    # its own nixpkgs (no `follows`) so the Rust toolchain it builds against
    # stays the one upstream tested. See modules/dev/herdr.nix.
    herdr.url = "github:herdrdev/herdr/v0.8.0";

    # Second agent harness, installed alongside opencode as a shadow. Pinned to
    # a release tag and left on its own nixpkgs (no `follows`) so it builds
    # against the toolchain upstream tested, as with herdr.
    pi = {
      url = "github:earendil-works/pi/v1.6.0";
    };

    # k3s test cluster on kepler runs each node as a NixOS MicroVM.
    # See docs/proposals/2026-06-19-kepler-k3s-microvm-cluster.md.
    microvm = {
      url = "github:microvm-nix/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake {inherit inputs;}
    (inputs.import-tree ./modules);
}
