profile := `hostname`

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
    statix check . -c .statix.toml -i '.direnv/*'

fmt:
    nix fmt ./

fmt-check:
    alejandra --check .

dry target=profile:
    sudo nixos-rebuild dry-build --flake .#{{target}} --show-trace

dry-all:
    sudo nixos-rebuild dry-build --flake .#pathfinder --show-trace
    sudo nixos-rebuild dry-build --flake .#discovery --show-trace

check:
    @echo ":: Linting..."
    just lint
    @echo ":: Checking format..."
    just fmt-check
    @echo ":: Dry building all hosts..."
    just dry-all
    @echo ":: All checks passed"

eval:
    nix flake check

# ── Remote Deployment ─────────────────────────────────────

deploy target ip port="22" user="erik":
    NIX_SSHOPTS="-p {{port}}" nixos-rebuild switch --flake .#{{target}} \
        --target-host {{user}}@{{ip}} \
        --use-remote-sudo --show-trace

deploy-boot target ip port="22" user="erik":
    NIX_SSHOPTS="-p {{port}}" nixos-rebuild boot --flake .#{{target}} \
        --target-host {{user}}@{{ip}} \
        --use-remote-sudo --show-trace

verify target ip port="22" user="erik":
    @echo ":: Verifying {{target}}..."
    ssh -p {{port}} {{user}}@{{ip}} "echo ':: Failed units:' && systemctl --failed --no-legend"
    ssh -p {{port}} {{user}}@{{ip}} "echo ':: Tailscale:' && tailscale status --peers=false"
    ssh -p {{port}} {{user}}@{{ip}} "echo ':: Syncthing:' && systemctl is-active syncthing"
    ssh -p {{port}} {{user}}@{{ip}} "echo ':: Home-manager:' && systemctl status home-manager-{{user}} --no-pager -n0"
    ssh -p {{port}} {{user}}@{{ip}} "echo ':: SOPS age key:' && test -f ~/.config/sops/age/keys.txt && echo 'present' || echo 'MISSING'"
    ssh -p {{port}} {{user}}@{{ip}} "echo ':: SOPS staging cleanup:' && test ! -f /var/lib/sops-staging/age-keys.txt && echo 'cleaned' || echo 'STILL EXISTS'"
    @echo ":: Verification complete for {{target}}"

nixos-anywhere target ip luks-pass="" user="nixos":
    #!/usr/bin/env bash
    set -euo pipefail
    LUKS_PASS="{{luks-pass}}"
    if [ -z "$LUKS_PASS" ]; then
        read -rsp "Enter LUKS password: " LUKS_PASS
        echo
    fi
    mkdir -p /tmp/nixos-extra/var/lib/sops-staging/
    cp ~/.config/sops/age/keys.txt /tmp/nixos-extra/var/lib/sops-staging/age-keys.txt
    chmod 600 /tmp/nixos-extra/var/lib/sops-staging/age-keys.txt
    LUKS_FILE=$(mktemp)
    printf '%s' "$LUKS_PASS" > "$LUKS_FILE"
    trap 'rm -f "$LUKS_FILE"; rm -rf /tmp/nixos-extra' EXIT
    nix run github:nix-community/nixos-anywhere -- \
        --flake .#{{target}} \
        --extra-files /tmp/nixos-extra \
        --disk-encryption-keys /tmp/luks-password.txt "$LUKS_FILE" \
        --show-trace \
        --generate-hardware-config nixos-generate-config \
            ./modules/hosts/{{target}}/_hw-generated.nix \
        {{user}}@{{ip}}

# ── Secrets ───────────────────────────────────────────────

age-private:
    mkdir -p ~/.config/sops/age
    nix run nixpkgs#ssh-to-age -- \
        -private-key -i ~/.ssh/id_ed25519 \
        > ~/.config/sops/age/keys.txt

age-public:
    nix shell nixpkgs#age -c age-keygen -y ~/.config/sops/age/keys.txt

sops:
    nix run nixpkgs#sops -- secrets/sops/secrets.yaml

rsync-sops ip port="22" user="erik":
    rsync -azv \
        --rsync-path="mkdir -p ~/.config/sops/age/ && rsync" \
        -e "ssh -l {{user}} -o Port={{port}}" \
        ~/.config/sops/age/ {{user}}@{{ip}}:~/.config/sops/age/

# ── Maintenance ───────────────────────────────────────────

gc days="5":
    nix-collect-garbage --delete-older-than {{days}}d

store-repair:
    sudo nix-store --verify --check-contents --repair
