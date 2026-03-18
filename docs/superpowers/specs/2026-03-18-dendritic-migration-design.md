# Dendritic Pattern Migration Design

Restructure the desktop-nixos repository to align with the dendritic pattern (flake-parts + import-tree), support both desktop and server hosts from a single repo, and migrate from Makefile to justfile.

## Goals

- Adopt `flake-parts` + `import-tree` for automatic module discovery
- Remove `specialArgs` in favor of top-level config options
- Separate desktop-only, server-only, and shared modules
- Support home lab server (virtualization/containers host) alongside existing desktop machines
- Split home-manager into base (all machines) and desktop (GUI machines) layers
- Host-specific configs for GPU, tailscale, syncthing, disko, DNS hosts, SSH profiles
- Replace Makefile with justfile including lint, format, and dry-build verification
- Split the monolithic `packages.nix` by role
- Each migration phase must pass `just check` before proceeding

## Two-Layer Module System

This is the key architectural concept. There are two distinct module systems at play:

### Layer 1: Flake-Parts Modules (top-level)

These are discovered by `import-tree` and operate at the **flake level**. They produce flake outputs (`nixosConfigurations`, `devShells`, `formatter`). They live in `modules/flake/`.

Files: `configurations.nix`, `dev-shell.nix`, `formatter.nix`

### Layer 2: NixOS Modules (per-host)

These are standard NixOS/home-manager modules. They operate **within** a `nixosSystem` evaluation and set options like `networking.*`, `boot.*`, `programs.*`. They are **NOT** discovered by import-tree. Instead, they are imported via a shared module list in the configurations declaration.

Files: everything under `modules/nixos/`, `modules/home-manager/`, `modules/hosts/`

### How they connect

```nix
# modules/flake/configurations.nix (flake-parts module)
config.flake.nixosConfigurations.workstation = lib.nixosSystem {
  modules = [
    ../nixos/default.nix          # aggregator: imports all shared NixOS modules
    ../hosts/workstation           # host-specific (has its own default.nix)
    ../users/erik.nix              # user account creation
    ../home-manager/nixos.nix      # HM wiring + layer selection
    inputs.disko.nixosModules.disko
    inputs.sops-nix.nixosModules.sops
    { repo.inputs = inputs; }
    { repo.secrets = builtins.fromJSON (builtins.readFile ../../secrets/crypt/secrets.json); }
  ];
};
```

**`modules/nixos/default.nix` is kept as an aggregator** — it imports all shared NixOS sub-modules (boot, networking, security, etc.). This is the one `default.nix` that remains. Category-level aggregators (`boot/default.nix`, `networking/default.nix`, etc.) are removed; the top-level aggregator lists individual files directly.

The flake-parts layer is thin (3-4 files). The NixOS layer is where all the real config lives.

## Flake Structure

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprland = {
      url = "git+https://github.com/hyprwm/Hyprland?submodules=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-colors.url = "github:misterio77/nix-colors";
    sops-nix.url = "github:Mic92/sops-nix";
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    flake-parts.url = "github:hercules-ci/flake-parts";
    import-tree.url = "github:vic/import-tree";
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; }
      (inputs.import-tree ./modules/flake);
}
```

Key differences from current flake:
- `import-tree` only scans `modules/flake/` (NOT the entire `modules/` tree)
- This avoids NixOS modules being treated as flake-parts modules
- `specialArgs` is gone — `inputs` is passed via a NixOS module (see below)
- The `secrets` JSON is read inside a NixOS module, not in flake.nix
- The broken `nixpkgs-unstable` overlay is removed (input doesn't exist)

## Passing Inputs Without specialArgs

A dedicated NixOS module makes inputs available to all other NixOS modules:

```nix
# modules/nixos/inputs.nix
{ lib, ... }:
{
  # Use _module.args to inject inputs into all NixOS modules
  # This replaces specialArgs = { inherit inputs; }
  options.repo = {
    inputs = lib.mkOption {
      type = lib.types.attrs;
      description = "Flake inputs, passed from configurations.nix";
    };
    secrets = lib.mkOption {
      type = lib.types.attrs;
      description = "Decrypted git-crypt secrets";
    };
  };
}
```

Set in the configurations.nix module list (shown in the "How they connect" section above). Any NixOS module then accesses `config.repo.inputs.home-manager`, `config.repo.secrets`, etc.

### Curried-inputs refactor

The current `modules/nixos/default.nix` uses a curried-inputs pattern: `inputs: {...}: { ... }`, imported as `(import ../../modules/nixos/default.nix inputs)`. The `desktop/default.nix` and `desktop/hyprland.nix` also use this pattern. All modules using this curried pattern must be rewritten to standard NixOS module form `{ config, lib, ... }: { ... }` and access inputs via `config.repo.inputs` instead. This is a Phase 1 task.

## Role System

```nix
# modules/nixos/roles.nix
{ lib, config, ... }:
{
  options.role = lib.mkOption {
    type = lib.types.enum [ "desktop" "server" ];
    description = "Machine role — controls which module sets are enabled";
  };
  options.isDesktop = lib.mkOption {
    type = lib.types.bool;
    default = config.role == "desktop";
    readOnly = true;
  };
  options.isServer = lib.mkOption {
    type = lib.types.bool;
    default = config.role == "server";
    readOnly = true;
  };
}
```

This replaces the current `modules.desktop.enable`, `modules.dev.enable`, `modules.audio.enable`, `modules.graphics.enable` option system. Instead of hosts opting in to individual feature groups, the role determines which modules activate. This is a deliberate simplification — the current per-module enable flags added boilerplate without real benefit since both desktop hosts always enabled the same set.

Note: `modules.audio.enable` is currently never set to `true` by either host — audio is effectively disabled. The migration fixes this: `pipewire.nix` moves to `modules/nixos/desktop/audio/` and gates on `config.isDesktop`, so all desktops get audio automatically.

## Module Layout

```
modules/
  flake/                            # FLAKE-PARTS modules (import-tree scans ONLY this)
    configurations.nix              # declares nixosConfigurations
    dev-shell.nix                   # devShell with statix, just
    formatter.nix                   # alejandra

  nixos/                            # NIXOS modules (imported by configurations.nix)
    default.nix                     # AGGREGATOR: imports all shared sub-modules below
    inputs.nix                      # repo.inputs + repo.secrets options
    meta.nix                        # repo.meta options (username, email, fullName)
    roles.nix                       # config.role, config.isDesktop, config.isServer
    packages/
      shared.nix                    # CLI tools, core utils, nix tools (all machines)
      desktop.nix                   # hyprland pkgs, GUI apps, themes (isDesktop only)
    boot/
      security.nix
      tmpfs.nix
    networking/
      firewall.nix                  # includes fail2ban
      openssh.nix                   # sshd hardening
      resolved.nix                  # DNS resolver
      tailscale.nix                 # shared enablement + firewall port
    security/
      apparmor.nix
      audit.nix
      issue.nix
      login.nix
      lynis.nix
      pam.nix
      polkit.nix
      sudo.nix
    services/
      atuin.nix
      avahi.nix
      file-systems.nix
      logrotate.nix
      maintenance.nix
      thunderbolt.nix
      xserver.nix
    hardware/
      bluetooth.nix
      peripherals.nix
      power.nix
      printing.nix
    graphics/
      common.nix                    # shared: opengl, mesa, vaapi
      nvidia.nix                    # nvidia driver, prime, power mgmt (exists)
      amd.nix                       # amdgpu, rocm (NEW — does not exist yet)
      intel.nix                     # intel media driver (exists)
    virtualization/
      containers.nix
      vms.nix
    dev/
      dotnet.nix
      go.nix
      java.nix
      javascript.nix
      paths.nix
      python.nix
    desktop/                        # ALL gated behind lib.mkIf config.isDesktop
      hyprland.nix
      sddm.nix
      fonts.nix
      xdg-portal.nix
      audio/
        pipewire.nix
    server/                         # ALL gated behind lib.mkIf config.isServer
      headless.nix                  # disable GUI, console defaults
      orchestration.nix             # podman/docker compose, VM management

  hosts/
    common.nix                      # timezone, nix settings, caches, gc, stateVersion, docs disable
    workstation/
      default.nix                   # role = "desktop", cpu microcode, kernel, hostName, boot, zram, autoUpgrade
      hardware-configuration.nix
      disk-config.nix
      graphics.nix                  # nvidia + PRIME config
      networking.nix                # /etc/hosts, firewall ports (80, 443, 22000, 21027)
      syncthing.nix                 # folders, device IDs
      tailscale.nix                 # client config
      ssh.nix                       # HM SSH Host entries for this machine
    laptop/
      default.nix                   # role = "desktop", cpu microcode, kernel, hostName
      hardware-configuration.nix
      disk-config.nix
      graphics.nix                  # intel iGPU
      networking.nix
      syncthing.nix
      tailscale.nix
      ssh.nix
    homelab/
      default.nix                   # role = "server", cpu microcode, kernel, hostName
      hardware-configuration.nix
      disk-config.nix
      graphics.nix                  # none or GPU passthrough
      networking.nix                # /etc/hosts for lab services
      tailscale.nix                 # subnet router, advertise routes
      ssh.nix                       # host entries for backup targets

  home-manager/                     # NOT scanned by import-tree
    nixos.nix                       # HM-as-NixOS-module wiring + layer selection
    base/                           # ALL machines (no role guard)
      shell/
        aliases.nix
        bash.nix
        fish.nix
      terminal/
        atuin.nix
        btop.nix
        direnv.nix
        starship.nix
        yazi.nix
        zoxide.nix
      ssh.nix                       # shared SSH client defaults + user-global Host entries (github)
      git.nix                       # git config (name, email, credential helper)
      gpg.nix                       # gpg + gpg-agent + ssh support
      nix-tools.nix                 # nix-index, command-not-found disable, nix-index timer
      bat.nix                       # bat config
      sops.nix                      # sops-nix config, age key, SSH key activation script
      packages.nix                  # CLI homePackages (monitoring, networking, gnu utils)
    desktop/                        # gated behind lib.mkIf config.isDesktop
      browser/
        brave.nix
      dev/
        vscode.nix
      terminal/
        ghostty.nix
        kitty.nix
      window-manager/
        hyprland.nix
        hypridle.nix
        hyprlock.nix
        hyprpaper.nix
        mako.nix
        waybar.nix
        wlogout.nix
        wofi.nix
        fonts.nix
        mime.nix
      theming.nix                   # GTK theme, nix-colors, qt6ct, cursor, icons
      clipboard.nix                 # cliphist service
      packages.nix                  # desktop homePackages (nordpass, ente-auth, cups, hplip)

  users/
    erik.nix                        # user account, shell, groups, SSH authorized keys
                                    # imported by configurations.nix per host

  overlays/                         # referenced by hosts/common.nix, not import-tree
    default.nix                     # cleaned up (remove broken nixpkgs-unstable ref)

  secrets/
    sops.nix                        # sops-nix NixOS module config (if any system-level secrets)
```

### What happened to `home/erik/default.nix`

The 197-line user config file is decomposed into the home-manager base/desktop layers:

| Current content | New location |
|----------------|--------------|
| `home.username`, `home.homeDirectory`, `home.stateVersion` | Set in `home-manager/nixos.nix` from `config.repo.meta` |
| `xdg` config | `home-manager/nixos.nix` (shared) |
| `programs.git` | `home-manager/base/git.nix` |
| `programs.gpg`, `services.gpg-agent` | `home-manager/base/gpg.nix` |
| `programs.nix-index`, nix-index timer | `home-manager/base/nix-tools.nix` |
| `sops` config + SSH key activation | `home-manager/base/sops.nix` |
| `home.file.".config/bat/config"` | `home-manager/base/bat.nix` |
| `home.file.".ssh/ro_config"` (SSH Host entries for github) | `home-manager/base/ssh.nix` (shared, not host-specific) |
| `home.file.".config/qt6ct/qt6ct.conf"` | `home-manager/desktop/theming.nix` |
| `services.cliphist` | `home-manager/desktop/clipboard.nix` |
| `colorScheme = tokyo-night-dark` | `home-manager/desktop/theming.nix` |

### What happened to `modules/home-manager/default.nix`

The current HM aggregator also contains inline config that needs mapping:

| Current content | New location |
|----------------|--------------|
| GTK theme config (gtk3, gtk4, dark theme, icons, cursors) | `home-manager/desktop/theming.nix` |
| `dconf.settings` dark mode | `home-manager/desktop/theming.nix` |
| `home.file.".config/keyboard"` | `home-manager/desktop/keyboard.nix` (path updates from `../../config/keyboard` to relative from new location) |
| `home.packages = packages.homePackages` | Split into `home-manager/base/packages.nix` + `home-manager/desktop/packages.nix` |
| Sub-module imports (window-manager, terminal, shell, dev, browser) | Handled by `base/default.nix` and `desktop/default.nix` aggregators |

### What happened to host-level imports

Current hosts import `modulesPath` profiles and external NixOS modules. These stay in host `default.nix` or move to `configurations.nix`:

| Current import | New location |
|---------------|--------------|
| `modulesPath + "/installer/scan/not-detected.nix"` | Keep in each host's `default.nix` |
| `modulesPath + "/profiles/qemu-guest.nix"` | Keep in each host's `default.nix` (only for hosts that are QEMU guests) |
| `inputs.home-manager.nixosModules.default` | Moved into `home-manager/nixos.nix` |
| `inputs.disko.nixosModules.disko` | Moved to `configurations.nix` module list |
| `inputs.sops-nix.nixosModules.sops` | Moved to `configurations.nix` module list |

### What happened to `hosts/common/global.nix`

Moves to `modules/hosts/common.nix` with all content preserved:

| Content | Notes |
|---------|-------|
| `time.timeZone` | Stays |
| `nixpkgs.config.allowUnfree` | Stays |
| `nixpkgs.overlays` | Wire overlays here (currently commented out, stays commented) |
| `documentation` disable | Stays |
| `nix.settings` (flakes, caches, trusted-users) | Stays |
| `nix.gc` | Stays |
| `system.stateVersion` | Stays |

### What happened to `packages.nix`

The 328-line monolith splits by role:

| Current section | New location | Role |
|----------------|--------------|------|
| `hyprlandPackages` | `modules/nixos/packages/desktop.nix` | desktop only |
| `systemPackages` (GUI items: kitty, ghostty, nautilus, blueman, etc.) | `modules/nixos/packages/desktop.nix` | desktop only |
| `systemPackages` (CLI tools: git, vim, ripgrep, fzf, etc.) | `modules/nixos/packages/shared.nix` | all machines |
| `systemPackages` (GUI libs: wlroots, xdg-portal-hyprland, themes) | `modules/nixos/packages/desktop.nix` | desktop only |
| `systemPackages` (hw tools: btrfs-progs, smartmontools, lm_sensors) | `modules/nixos/packages/shared.nix` | all machines |
| `nixPackages` | `modules/nixos/packages/shared.nix` | all machines |
| `discretionaryPackages` (GUI: discord, spotify, brave, gparted) | `modules/nixos/packages/desktop.nix` | desktop only |
| `discretionaryPackages` (CLI: lazygit, fastfetch, terraform, k8s) | `modules/nixos/packages/shared.nix` | all machines |
| `homePackages` (CLI: bat, jq, mtr, nmap, strace) | `modules/home-manager/base/packages.nix` | all machines |
| `homePackages` (printing: cups, hplip) | `modules/home-manager/desktop/packages.nix` | desktop only |

### Home-Manager Wiring

Host-specific SSH modules cannot use string interpolation in import paths (Nix resolves paths at parse time). Instead, each host's SSH module is passed from `configurations.nix`:

```nix
# modules/flake/configurations.nix passes the SSH module per host:
config.flake.nixosConfigurations.workstation = lib.nixosSystem {
  modules = [
    # ... other modules ...
    (import ../home-manager/nixos.nix {
      hostSshModule = ../hosts/workstation/ssh.nix;
    })
  ];
};
```

```nix
# modules/home-manager/nixos.nix
{ hostSshModule }: { config, lib, ... }:
let
  inputs = config.repo.inputs;
in
{
  imports = [
    inputs.home-manager.nixosModules.default
  ];

  config = {
    home-manager = {
      useGlobalPkgs = true;
      backupFileExtension = "backup";

      users.${config.repo.meta.owner.username} = {
        imports =
          # Always: base layer (has its own default.nix aggregator)
          [ ./base ]
          # Always: nix-colors + sops HM modules
          ++ [ inputs.nix-colors.homeManagerModules.default ]
          ++ [ inputs.sops-nix.homeManagerModules.sops ]
          # Desktop: GUI layer (has its own default.nix aggregator)
          ++ lib.optionals config.isDesktop [ ./desktop ]
          # Host-specific SSH entries (passed from configurations.nix)
          ++ [ hostSshModule ];

        home.username = config.repo.meta.owner.username;
        home.homeDirectory = "/home/${config.repo.meta.owner.username}";
        home.stateVersion = config.system.stateVersion;
        home.enableNixpkgsReleaseCheck = false;

        xdg = {
          enable = true;
          userDirs = { enable = true; createDirectories = true; };
        };

        programs.home-manager.enable = true;

        # nix-colors theme (used by desktop modules when present)
        colorScheme = inputs.nix-colors.colorSchemes.tokyo-night-dark;
      };
    };
  };
}
```

Note: Both `home-manager/base/` and `home-manager/desktop/` need a `default.nix` aggregator that imports all files in their directory. These are the standard HM import entry points. `home-manager/desktop/` modules also use `lib.mkIf config.isDesktop` internally as a safety guard.

### Metadata Module

```nix
# modules/nixos/meta.nix (NixOS module, NOT flake-parts)
{ lib, ... }:
{
  options.repo.meta = {
    owner = {
      username = lib.mkOption { type = lib.types.str; default = "erik"; };
      fullName = lib.mkOption { type = lib.types.str; default = "Erik Bogado"; };
      email = lib.mkOption { type = lib.types.str; default = "erikbogado@gmail.com"; };
    };
  };
}
```

Uses the `repo.*` namespace to avoid colliding with flake-parts' `flake.*` namespace.

### SSH Three-Layer Split

| Layer | Location | Content |
|-------|----------|---------|
| sshd hardening | `modules/nixos/networking/openssh.nix` | Shared daemon config (key-only auth, algorithms) |
| ssh client defaults + user-global hosts | `modules/home-manager/base/ssh.nix` | Shared client options (compression, keepalive) + GitHub Host entries (same on all machines) |
| per-machine host entries | `modules/hosts/*/ssh.nix` | Machine-specific Host blocks (homelab, backup, etc.) |

### GPU Three-Driver Support

Host sets `modules.graphics.driver = "nvidia" | "amd" | "intel" | "none"`. The current enum only has `["intel" "nvidia" "none"]` — `"amd"` and `amd.nix` are new additions in Phase 2. CPU microcode is a one-liner in each host's `default.nix`.

### NixOS Aggregator Module

```nix
# modules/nixos/default.nix — the ONE aggregator that remains
{ ... }:
{
  imports = [
    ./inputs.nix
    ./meta.nix
    ./roles.nix
    ./packages/shared.nix
    ./packages/desktop.nix
    ./boot/security.nix
    ./boot/tmpfs.nix
    ./networking/firewall.nix
    ./networking/openssh.nix
    ./networking/resolved.nix
    ./networking/tailscale.nix
    ./security/apparmor.nix
    ./security/audit.nix
    # ... all other shared modules listed explicitly
    ./desktop/hyprland.nix
    ./desktop/sddm.nix
    ./desktop/fonts.nix
    ./desktop/xdg-portal.nix
    ./desktop/audio/pipewire.nix
    ./server/headless.nix
    ./server/orchestration.nix
    ./graphics/common.nix
    ./graphics/nvidia.nix
    ./graphics/intel.nix
    ./graphics/amd.nix
    ./virtualization/containers.nix
    ./virtualization/vms.nix
    # ... etc
  ];
}
```

This replaces the current chain of `default.nix` aggregators in each subdirectory. One flat list is easier to maintain and makes dependencies explicit.

### system.autoUpgrade

The `--impure` flag is currently in `system.autoUpgrade.flags` on both hosts. After removing `specialArgs` and the `secrets` builtins.readFile from flake.nix, `--impure` should no longer be needed. Each host's `default.nix` must be updated to remove it:

```nix
system.autoUpgrade = {
  enable = true;
  flake = "github:ErikBPF/desktop-nixos#workstation";
  operation = "switch";
  flags = [ "--show-trace" ];  # removed --impure
  allowReboot = false;
  dates = "05:00";
};
```

### Overlay Cleanup

The current `overlays/default.nix` references `inputs.nixpkgs-unstable` which doesn't exist (input is commented out in flake.nix). The overlay is effectively broken. Clean it up:

- Remove the `unstable-packages` overlay
- Keep the file as a skeleton for future overlays
- If an unstable overlay is actually needed later, add the input back

## Justfile

Replaces Makefile. Key improvements: no unnecessary sudo, no --impure, added verification targets, parameterized defaults.

```just
profile := `hostname`
host_ip := "192.168.10.147"
nixos_user := "nixos"

default:
    @just --list

# ── Local System ──────────────────────────────────────────

build target=profile:
    sudo nixos-rebuild switch --flake .#{{target}} --show-trace

boot target=profile:
    sudo nixos-rebuild boot --flake .#{{target}} --show-trace

update:
    nix flake update

upgrade target=profile:
    nix flake update
    sudo nixos-rebuild switch --flake .#{{target}} --show-trace

# ── Verification ──────────────────────────────────────────

lint:
    statix check .

fmt:
    nix fmt ./

fmt-check:
    nix fmt -- --check ./

dry target=profile:
    sudo nixos-rebuild dry-build --flake .#{{target}} --show-trace

dry-all:
    sudo nixos-rebuild dry-build --flake .#workstation --show-trace
    sudo nixos-rebuild dry-build --flake .#laptop --show-trace
    sudo nixos-rebuild dry-build --flake .#homelab --show-trace

check:
    @echo ":: Linting..."
    statix check .
    @echo ":: Checking format..."
    nix fmt -- --check ./
    @echo ":: Dry building all hosts..."
    just dry-all
    @echo ":: All checks passed"

eval:
    nix flake check

# ── Remote Deployment ─────────────────────────────────────

nixos-anywhere target=profile ip=host_ip user=nixos_user:
    nix run github:nix-community/nixos-anywhere -- \
        --flake .#{{target}} \
        --show-trace \
        --generate-hardware-config nixos-generate-config \
            ./modules/hosts/{{target}}/hardware-configuration.nix \
        {{user}}@{{ip}}

# ── Secrets ───────────────────────────────────────────────

unlock:
    git-crypt unlock ./secret-key
    @echo "Unlocked. Run: just build"

age-private:
    mkdir -p ~/.config/sops/age
    nix run nixpkgs#ssh-to-age -- \
        -private-key -i ~/.ssh/id_ed25519 \
        > ~/.config/sops/age/keys.txt

age-public:
    nix shell nixpkgs#age -c age-keygen -y ~/.config/sops/age/keys.txt

sops:
    nix run nixpkgs#sops -- secrets/sops/secrets.yaml

rsync-sops ip=host_ip user=nixos_user:
    rsync -azv \
        --rsync-path="mkdir -p ~/.config/sops/age/ && rsync" \
        -e "ssh -l {{user}} -o Port=22" \
        ~/.config/sops/age/ {{user}}@{{ip}}:~/.config/sops/age/

rsync-crypt ip=host_ip user=nixos_user:
    @test -f ./secret-key-base64 || (cat ./secret-key | base64 -w 0 > ./secret-key-base64)
    scp ./secret-key-base64 {{user}}@{{ip}}:~/secret-key-base64
    ssh {{user}}@{{ip}} "cat ~/secret-key-base64 | base64 --decode > ~/secret-key && chmod 600 ~/secret-key"
    @echo "Key deployed. On remote run: git-crypt unlock ~/secret-key"

# ── Maintenance ───────────────────────────────────────────

gc days="5":
    nix-collect-garbage --delete-older-than {{days}}d

store-repair:
    sudo nix-store --verify --check-contents --repair
```

Changes from Makefile:
- No `sudo` on `update`, `fmt`, `lint`, `age-*`, `sops`
- `dry-build` uses `sudo` (needed for system-level evaluation)
- No `--impure` flag
- No `--extra-experimental-features` flags (already in nix config)
- Removed `update-channel` (not needed with flakes)
- Removed `any-update` (deploy-rs not wired up)
- Added `lint`, `fmt-check`, `dry`, `dry-all`, `check`, `eval` targets
- `gc` takes optional days parameter (default 5)
- `nixos-anywhere` path updated to `modules/hosts/`

### Dev Shell

```nix
# modules/flake/dev-shell.nix (flake-parts module)
{ inputs, ... }:
{
  perSystem = { pkgs, ... }: {
    devShells.default = pkgs.mkShell {
      packages = with pkgs; [ statix just alejandra ];
    };
  };
}
```

Note: `just check` requires `statix` and `just` to be available. Enter the dev shell first: `nix develop` or use `direnv` with a `.envrc` containing `use flake`.

## Migration Phases

### Phase 1 — Flake Restructure

- Add `flake-parts` and `import-tree` to flake inputs
- Create `modules/flake/` with `configurations.nix`, `dev-shell.nix`, `formatter.nix`
- Rewrite `flake.nix` outputs to use `flake-parts.lib.mkFlake` scanning only `modules/flake/`
- Create `modules/nixos/inputs.nix` (repo.inputs + repo.secrets options)
- Create `modules/nixos/meta.nix` (repo.meta options)
- Create `modules/nixos/roles.nix` (role option, both hosts set `role = "desktop"`)
- **Rewrite curried-inputs modules**: convert `modules/nixos/default.nix`, `modules/nixos/desktop/default.nix`, and `modules/nixos/desktop/hyprland.nix` from `inputs: {...}: { ... }` to standard `{ config, lib, ... }: { ... }` form, using `config.repo.inputs` for input access
- Move `hosts/` to `modules/hosts/`, update all relative import paths
- Move `home/erik/` content preparation (keep file for now, decompose in Phase 2)
- Update host `default.nix` files to use `config.repo.inputs` instead of bare `inputs`
- Move disko/sops-nix NixOS module imports from hosts into `configurations.nix`
- Preserve `modulesPath` imports (`not-detected.nix`, `qemu-guest.nix`) in host defaults
- Remove `specialArgs` and `home-manager.extraSpecialArgs` from host configs
- Remove `--impure` from `system.autoUpgrade.flags` on both hosts
- Clean up `overlays/default.nix` (remove broken nixpkgs-unstable reference)
- Create `justfile`, keep `Makefile` temporarily until verified
- Create `modules/flake/dev-shell.nix` with statix + just + alejandra
- Gate: `nix develop -c just dry workstation && nix develop -c just dry laptop`

### Phase 2 — Module Reorganization

- Remove category-level `default.nix` aggregators (`boot/default.nix`, `networking/default.nix`, etc.)
- Rewrite `modules/nixos/default.nix` to be a flat aggregator listing all individual module files
- Move desktop-only NixOS modules into `modules/nixos/desktop/`:
  - `hyprland.nix`, `sddm.nix`, `fonts.nix`, `xdg-portal.nix`, `pipewire.nix`
- Add `lib.mkIf config.isDesktop` guards to desktop NixOS modules
- Remove old `modules.audio.enable`, `modules.desktop.enable`, `modules.dev.enable` options (replaced by role system)
- Split `packages.nix` into `modules/nixos/packages/shared.nix` and `modules/nixos/packages/desktop.nix`
- Split home-manager into `base/` and `desktop/`:
  - base: shell/, terminal/, git.nix, gpg.nix, nix-tools.nix, bat.nix, sops.nix, ssh.nix, packages.nix
  - desktop: window-manager/*, browser/brave, dev/vscode, terminal/ghostty, terminal/kitty, theming.nix, clipboard.nix, keyboard.nix, packages.nix
- Create `home-manager/base/default.nix` and `home-manager/desktop/default.nix` aggregators
- Decompose `home/erik/default.nix` into the above base/desktop files (see mapping table)
- Decompose `modules/home-manager/default.nix` content: GTK/dconf into theming.nix, keyboard into keyboard.nix (update relative path from `../../config/keyboard` to new location)
- Create `modules/home-manager/nixos.nix` with layer selection logic, nix-colors/sops imports, and curried hostSshModule parameter
- Extract host-specific configs into host directories:
  - Each host gets `graphics.nix`, `networking.nix`, `ssh.nix`, `tailscale.nix`, `syncthing.nix`
- Move GitHub SSH Host entries to `modules/home-manager/base/ssh.nix` (shared, not host-specific)
- Create `modules/nixos/graphics/{common,amd}.nix` (nvidia.nix and intel.nix already exist)
- Extend graphics driver enum to include `"amd"`
- Ensure fail2ban config preserved in `modules/nixos/networking/firewall.nix`
- Move overlays into `modules/overlays/`
- Remove old `Makefile`, `home/` directory, old `modules/packages.nix`
- Gate: `nix develop -c just check` (lint + format + dry-build workstation + laptop)

### Phase 3 — Add Server Support

- Create `modules/nixos/server/headless.nix` — disable GUI, console font, serial console
- Create `modules/nixos/server/orchestration.nix` — podman/docker compose, VM management defaults
- Create `modules/hosts/homelab/`:
  - `default.nix` with `role = "server"`, cpu microcode, kernel, hostName
  - `hardware-configuration.nix`
  - `disk-config.nix`
  - `graphics.nix` — none or passthrough
  - `networking.nix` — /etc/hosts, firewall ports for services
  - `tailscale.nix` — subnet router config
  - `ssh.nix` — host entries for backup targets
- Register homelab in `modules/flake/configurations.nix`
- Update `just dry-all` to include homelab
- Gate: `nix develop -c just check` passes for all three hosts

## What Does Not Change

- Secrets files (`secrets/crypt/secrets.json`, `secrets/sops/secrets.yaml`, `.sops.yaml`) — stay at repo root
- Config files (`config/` directory with wallpapers, waybar, keyboard) — stays at repo root
- Disko integration — stays per-host, moves into `modules/hosts/`
- nix-colors integration — preserved, imported in `home-manager/nixos.nix`
- sops-nix integration — preserved at both NixOS and HM levels

## Risk Mitigation

- Each phase ends with `just check` or `just dry` (lint + format + dry-build)
- Phase 1 is purely structural — same modules, different wiring
- Phase 2 is file moves + adding guards — no logic changes
- Phase 3 is additive — new host, existing hosts untouched
- Git commits at each phase boundary for easy rollback
- `Makefile` kept in Phase 1 as fallback, removed only in Phase 2 after justfile verified
