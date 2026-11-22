{
	pkgs ? import <nixpkgs> { },
}:
let
	inherit (pkgs)
		lib
		buildNpmPackage
		nodejs_22
		makeWrapper
		;
in
buildNpmPackage {
	pname = "pi-harness";
	version = "0.1.0";

	src = ./.;
	nodejs = nodejs_22;

	# Filled from the build's reported hash, never guessed.
	npmDepsHash = "sha256-HINmNBS4oF+bGNx3kgqJuVHjDVVgt+o5kfrdktFg8BE=";

	nativeBuildInputs = [ makeWrapper ];

	postInstall = ''
		wrapProgram $out/bin/pi-harness \
			--prefix PATH : ${lib.makeBinPath [ nodejs_22 ]}
	'';

	meta = {
		description = "Pi-native durable coding harness for the homelab gateways";
		mainProgram = "pi-harness";
	};
}
