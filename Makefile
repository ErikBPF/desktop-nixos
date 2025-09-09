
update: 
	sudo nix flake update
	
build:
	git pull;
	sudo nixos-rebuild switch --flake .#workstation --impure --show-trace

fmt:
	# format the nix files in this repo
	nix fmt ./

gc: 
	# run garbage collection
	nix-collect-garbage --delete-older-than 5d

any-install:
	sudo nix  --extra-experimental-features flakes --extra-experimental-features nix-command  run nixpkgs#nixos-anywhere --  --flake .#workstation --generate-hardware-config nixos-generate-config ./hosts/workstation/hardware-configuration.nix nixos@192.168.10.125

store-repair:
	sudo nix-store --verify --check-contents --repair

check:
	sudo nix  config check --extra-experimental-features flakes --extra-experimental-features nix-command 

any-update:
	sudo nix  --extra-experimental-features flakes --extra-experimental-features nix-command run github:serokell/deploy-rs .#workstation#192.168.10.125

age-private:
	mkdir -p ~/.config/sops/age;
	sudo nix  --extra-experimental-features flakes --extra-experimental-features nix-command  run nixpkgs#ssh-to-age -- -private-key -i ~/.ssh/id_ed25519 > ~/.config/sops/age/keys.txt

age-public:
	sudo nix  --extra-experimental-features flakes --extra-experimental-features nix-command shell nixpkgs#age -c age-keygen -y ~/.config/sops/age/keys.txt

sops:
	sudo nix  --extra-experimental-features flakes --extra-experimental-features nix-command run nixpkgs#sops -- secrets/secrets.yaml

# rsync:
#     rsync -azv --rsync-path="mkdir -p ~/.config/sops/age/ && rsync" --filter=':- .gitignore' -e "ssh -l erik -oport=22" ~/.config/sops/age/ erik@192.168.10.125:~/.config/sops/age/


