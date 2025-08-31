add-ssh:
	ssh-copy-id nixos@192.168.10.125

ssh:
	ssh nixos@192.168.10.125

build:
	sudo nixos-rebuild switch --flake .#workstation --impure

update:
	sudo nix  --extra-experimental-features flakes --extra-experimental-features nix-command  run nixpkgs#nixos-rebuild switch --flake .#workstation --target-host erik@192.168.10.125 --use-remote-sudo --show-trace
develop:
	sudo nix  --extra-experimental-features flakes --extra-experimental-features nix-command develop

any-install-nixos:
	sudo nix  --extra-experimental-features flakes --extra-experimental-features nix-command  run nixpkgs#nixos-anywhere --  --flake .#workstation --generate-hardware-config nixos-generate-config ./hosts/workstation/hardware-configuration.nix nixos@192.168.10.125

gc:
	sudo nix store gc --extra-experimental-features nix-command

store-repair:
	sudo nix-store --verify --check-contents --repair

check:
	sudo nix  config check --extra-experimental-features flakes --extra-experimental-features nix-command 