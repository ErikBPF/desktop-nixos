prepare-disk:
	sudo nix --experimental-features "nix-command flakes" run github:nix-community/disko -- --mode disko ./hosts/laptop/disk.nix

install:
	nixos-install --root /mnt --flake ./#laptop