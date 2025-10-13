inputs: {...}: {
  imports = [
    # System packages and programs
    ./system-packages.nix

    # Core system categories
    ./audio
    ./boot
    (import ./desktop inputs)
    ./dev
    ./graphics
    ./hardware
    ./networking
    ./security
    ./services
    ./virtualization
  ];
}
