# Configuration variables - can be overridden on command line
# Example: make build PROFILE=laptop
PROFILE ?= laptop
HOST_IP ?= 192.168.10.147
NIXOS_USER ?= erik

.PHONY: help update build boot upgrade fmt gc nixos-anywhere store-repair check any-update age-private age-public sops unlock rsync-sops rsync-crypt

help:
	@echo "NixOS Configuration Management"
	@echo ""
	@echo "Configuration Variables:"
	@echo "  PROFILE=$(PROFILE)  - Target system profile (workstation, laptop, etc.)"
	@echo "  HOST_IP=$(HOST_IP)  - Target host IP address"
	@echo "  NIXOS_USER=$(NIXOS_USER)        - Remote user for deployments"
	@echo ""
	@echo "Usage Examples:"
	@echo "  make build                                    - Build and switch current system"
	@echo "  make build PROFILE=laptop                     - Build laptop profile"
	@echo "  make nixos-anywhere PROFILE=laptop HOST_IP=192.168.1.100  - Deploy to remote"
	@echo ""
	@echo "Available targets:"
	@echo "  Local System:"
	@echo "    build      - Build and switch to new configuration"
	@echo "    boot       - Build for next boot"
	@echo "    update     - Update flake inputs"
	@echo "    upgrade    - Full system upgrade"
	@echo "    gc         - Garbage collection"
	@echo ""
	@echo "  Remote Deployment:"
	@echo "    nixos-anywhere  - Deploy to remote system via nixos-anywhere"
	@echo ""
	@echo "  Secrets Management:"
	@echo "    unlock          - Unlock git-crypt encrypted files"
	@echo "    age-private     - Generate Age private key from SSH key"
	@echo "    age-public      - Display Age public key"
	@echo "    sops            - Edit SOPS encrypted secrets"
	@echo "    rsync-sops      - Sync SOPS age keys to remote host"
	@echo "    rsync-crypt     - Transfer and decode git-crypt key to remote host"
	@echo ""
	@echo "  Maintenance:"
	@echo "    fmt         - Format Nix files"
	@echo "    store-repair - Verify and repair Nix store"
	@echo "    check       - Check Nix configuration"
	@echo ""
	@echo "NOTE: Before building, unlock git-crypt with: make unlock"

update: 
	
	sudo nix flake update
	
build:
	# git pull;
	# git-crypt unlock ./secret-key
	sudo nixos-rebuild switch --flake .#$(PROFILE) --impure --show-trace

boot:
	git pull;
	# git-crypt unlock ./secret-key
	sudo nixos-rebuild boot --flake .#$(PROFILE) --impure --show-trace

upgrade:
	git pull;
	sudo nixos-rebuild switch --upgrade-all --flake .#$(PROFILE) --impure --show-trace

fmt:
	# format the nix files in this repo
	nix fmt ./

update-channel:
	sudo nix-channel --add https://nixos.org/channels/nixos-unstable nixos
	sudo nix-channel --update

gc: 
	# run garbage collection
	nix-collect-garbage --delete-older-than 5d

nixos-anywhere:
	@echo "Deploying $(PROFILE) to $(NIXOS_USER)@$(HOST_IP)"
	nix run github:nix-community/nixos-anywhere -- \
		--flake .#$(PROFILE) \
		--show-trace \
		--option extra-experimental-features "nix-command flakes" \
		--option pure-eval false \
		--generate-hardware-config nixos-generate-config ./hosts/$(PROFILE)/hardware-configuration.nix \
		$(NIXOS_USER)@$(HOST_IP)

store-repair:
	sudo nix-store --verify --check-contents --repair

check:
	sudo nix  config check --extra-experimental-features flakes --extra-experimental-features nix-command 

any-update:
	sudo nix  --extra-experimental-features flakes --extra-experimental-features nix-command run github:serokell/deploy-rs .#$(PROFILE)#$(HOST_IP)

age-private:
	mkdir -p ~/.config/sops/age;
	sudo nix  --extra-experimental-features flakes --extra-experimental-features nix-command  run nixpkgs#ssh-to-age -- -private-key -i ~/.ssh/id_ed25519 > ~/.config/sops/age/keys.txt

age-public:
	sudo nix  --extra-experimental-features flakes --extra-experimental-features nix-command shell nixpkgs#age -c age-keygen -y ~/.config/sops/age/keys.txt

sops:
	sudo nix  --extra-experimental-features flakes --extra-experimental-features nix-command run nixpkgs#sops -- secrets/sops/secrets.yaml

unlock:
	@echo "Unlocking git-crypt encrypted files..."
	git-crypt unlock ./secret-key
	@echo "✓ Git-crypt unlocked successfully"
	@echo "You can now run: make build"

rsync-sops:
	rsync -azv --rsync-path="mkdir -p ~/.config/sops/age/ && rsync" \
		--filter=':- .gitignore' -e "ssh -l $(NIXOS_USER) -oport=22" \
		~/.config/sops/age/ $(NIXOS_USER)@$(HOST_IP):~/.config/sops/age/

rsync-crypt:
	@echo "Transferring git-crypt key to $(NIXOS_USER)@$(HOST_IP)..."
	@if [ ! -f ./secret-key-base64 ]; then \
		echo "Creating base64 encoded key from ./secret-key"; \
		cat ./secret-key | base64 -w 0 > ./secret-key-base64; \
	fi
	scp ./secret-key-base64 $(NIXOS_USER)@$(HOST_IP):~/secret-key-base64
	@echo "Decoding git-crypt key on remote..."
	ssh $(NIXOS_USER)@$(HOST_IP) "cat ~/secret-key-base64 | base64 --decode > ~/secret-key && chmod 600 ~/secret-key"
	@echo "✓ Git-crypt key deployed successfully"
	@echo "On remote, run: git-crypt unlock ~/secret-key"


