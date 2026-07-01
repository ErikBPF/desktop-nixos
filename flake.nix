{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

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
