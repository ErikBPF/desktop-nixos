add-ssh:
	ssh-copy-id nixos@192.168.10.125

ssh:
	ssh nixos@192.168.10.125

any-install:
	sudo nix  --extra-experimental-features flakes --extra-experimental-features nix-command  run github:nix-community/nixos-anywhere -- --flake .#workstation erik@192.168.10.125

develop:
	sudo nix  --extra-experimental-features flakes --extra-experimental-features nix-command develop

any-install-nixos:
	sudo nix  --extra-experimental-features flakes --extra-experimental-features nix-command  run nixpkgs#nixos-anywhere --  --flake .#generic --generate-hardware-config nixos-generate-config ./hardware-configuration.nix nixos@192.168.10.125

gc:
	sudo nix store gc --extra-experimental-features nix-command

store-repair:
	sudo nix-store --verify --check-contents --repair

check:
	sudo nix  config check --extra-experimental-features flakes --extra-experimental-features nix-command 