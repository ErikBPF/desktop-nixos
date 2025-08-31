
update: 
	sudo nix flake update
	
build:
	git pull;
	sudo nixos-rebuild switch --flake .#workstation --impure

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