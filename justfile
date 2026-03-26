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
    statix check . -c .statix.toml -i 'modules/_*' 'home/*' 'hosts/*' 'overlays/*'

fmt:
    nix fmt ./

fmt-check:
    alejandra --check -e ./modules/_nixos -e ./modules/_home-manager -e ./modules/_users -e ./modules/_packages.nix -e ./home -e ./hosts -e ./overlays .

dry target=profile:
    sudo nixos-rebuild dry-build --flake .#{{target}} --show-trace

dry-all:
    sudo nixos-rebuild dry-build --flake .#pathfinder --show-trace

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

deploy target ip user="erik":
    nixos-rebuild switch --flake .#{{target}} \
        --target-host {{user}}@{{ip}} \
        --use-remote-sudo --show-trace

deploy-boot target ip user="erik":
    nixos-rebuild boot --flake .#{{target}} \
        --target-host {{user}}@{{ip}} \
        --use-remote-sudo --show-trace

verify target ip user="erik":
    @echo ":: Verifying {{target}}..."
    ssh {{user}}@{{ip}} "echo ':: Failed units:' && systemctl --failed --no-legend"
    ssh {{user}}@{{ip}} "echo ':: Tailscale:' && tailscale status --peers=false"
    ssh {{user}}@{{ip}} "echo ':: Syncthing:' && systemctl is-active syncthing"
    ssh {{user}}@{{ip}} "echo ':: SOPS age key:' && test -f ~/.config/sops/age/keys.txt && echo 'present' || echo 'MISSING'"
    @echo ":: Verification complete for {{target}}"

nixos-anywhere target ip user="nixos":
    mkdir -p /tmp/nixos-extra/home/erik/.config/sops/age/
    cp ~/.config/sops/age/keys.txt /tmp/nixos-extra/home/erik/.config/sops/age/
    nix run github:nix-community/nixos-anywhere -- \
        --flake .#{{target}} \
        --extra-files /tmp/nixos-extra \
        --show-trace \
        --generate-hardware-config nixos-generate-config \
            ./modules/hosts/{{target}}-hw-generated.nix \
        {{user}}@{{ip}}
    rm -rf /tmp/nixos-extra

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

rsync-sops ip user="erik":
    rsync -azv \
        --rsync-path="mkdir -p ~/.config/sops/age/ && rsync" \
        -e "ssh -l {{user}} -o Port=22" \
        ~/.config/sops/age/ {{user}}@{{ip}}:~/.config/sops/age/

rsync-crypt ip user="erik":
    @test -f ./secret-key-base64 || (cat ./secret-key | base64 -w 0 > ./secret-key-base64)
    scp ./secret-key-base64 {{user}}@{{ip}}:~/secret-key-base64
    ssh {{user}}@{{ip}} "cat ~/secret-key-base64 | base64 --decode > ~/secret-key && chmod 600 ~/secret-key"
    @echo "Key deployed. On remote run: git-crypt unlock ~/secret-key"

# ── Maintenance ───────────────────────────────────────────

gc days="5":
    nix-collect-garbage --delete-older-than {{days}}d

store-repair:
    sudo nix-store --verify --check-contents --repair
