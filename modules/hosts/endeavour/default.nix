{
  config,
  inputs,
  ...
}: let
  flakeConfig = config;
  m = flakeConfig.flake.modules;
in {
  configurations.nixos.endeavour.module = {
    config,
    pkgs,
    modulesPath,
    ...
  }: let
    # OCR resolves its LiteLLM key at run time from the login environment
    # (already sourced from OpenBao), so the key never lands in
    # ~/.opencodereview/config.json.
    ocrLitellmKey = pkgs.writeShellScriptBin "ocr-litellm-key" ''
      set -eu
      if [ -z "''${LITELLM_OCR_API_KEY:-}" ]; then
        echo "ocr-litellm-key: LITELLM_OCR_API_KEY is unset; run ocr from a login shell" >&2
        exit 1
      fi
      printf '%s' "$LITELLM_OCR_API_KEY"
    '';
  in {
    imports = [
      (modulesPath + "/installer/scan/not-detected.nix")
      inputs.disko.nixosModules.disko
      inputs.sops-nix.nixosModules.sops
      m.nixos.profile-base
      m.nixos.profile-desktop
      m.nixos.erik-vault-agent
      m.nixos.erik-secretspec
      m.nixos.desktop-workspaces
      m.nixos.endeavour-hardware
      m.nixos.endeavour-networking
      m.nixos.endeavour-always-on
      m.nixos.netbird-client
      m.nixos.endeavour-ubuntu-work
      m.nixos.endeavour-syncthing
      m.nixos.first-boot
      m.nixos.pangolin-newt
      m.nixos.alloy
      m.nixos.endeavour-host-integrity
      m.nixos.kepler-nfs
      m.nixos.btrfs-snapshots
      m.nixos.endeavour-home-backup
      m.nixos.sccache-client
      m.nixos.harbor-reader
    ];

    home-manager.users.${flakeConfig.username} = {
      config,
      lib,
      pkgs,
      ...
    }: let
      sk = pkgs.writeShellScriptBin "sk" ''
        if (( $# > 0 )); then
          if [ -t 0 ] && [ -t 1 ]; then
            exec ${pkgs.openssh}/bin/ssh -o RequestTTY=yes kepler "$@"
          fi
          exec ${pkgs.openssh}/bin/ssh kepler "$@"
        fi
        exec ${config.home.profileDirectory}/bin/desktop-workspaces remote
      '';
      terminal = "${config.programs.ghostty.package}/bin/ghostty +new-window";
    in {
      imports = [
        inputs.nix-colors.homeManagerModules.default
        m.home.profile-desktop
        m.home.bluetooth-prompts
        m.home.captive-portal
        m.home.kindle-auto-eject
        m.home.desktop-workspaces
        m.home.deepseek-harness
        m.home.monitor-layout-docked
        m.home.voice-dictation
      ];
      inherit (flakeConfig) colorScheme;

      home.packages = [sk ocrLitellmKey];

      # Open Code Review provider routing for the /cr pre-pass. Only the
      # endpoint and model are declared here; the key comes from the helper.
      home.file.".opencodereview/config.json".text = builtins.toJSON {
        provider = "litellm";
        providers.litellm = {
          url = "https://litellm.homelab.pastelariadev.com/v1";
          model = "glm-5.3";
          api_key_cmd = "${ocrLitellmKey}/bin/ocr-litellm-key";
          # The gateway routes per session; the placeholder keeps one value
          # per OCR run, the same contract as opencode's gateway plugin.
          extra_headers = {"x-opencode-session" = "{ocr_session_key}";};
        };
      };

      wayland.windowManager.hyprland.settings = {
        # Override desktop-workspaces' forced local terminal on this client.
        terminal = lib.mkOverride 40 {_var = "${terminal} -e ${sk}/bin/sk";};
        bind = [
          {
            _args = [
              "SUPER + SHIFT + T"
              (lib.generators.mkLuaInline ''hl.dsp.exec_cmd("${terminal}")'')
            ];
          }
        ];
      };
    };

    # Only the read-only AppRole credentials are bootstrap material. The token
    # itself is written out of band and never enters this repo.

    sops.secrets."openbao-harbor-reader-endeavour-role-id" = {
      sopsFile = ../../../secrets/sops/secrets.yaml;
      key = "openbao_harbor_reader_endeavour_role_id";
      owner = flakeConfig.username;
      mode = "0400";
    };
    sops.secrets."openbao-harbor-reader-endeavour-secret-id" = {
      sopsFile = ../../../secrets/sops/secrets.yaml;
      key = "openbao_harbor_reader_endeavour_secret_id";
      owner = flakeConfig.username;
      mode = "0400";
    };
    services.harborReader = {
      enable = true;
      address = "https://openbao.homelab.pastelariadev.com";
      roleIdFile = config.sops.secrets.openbao-harbor-reader-endeavour-role-id.path;
      secretIdFile = config.sops.secrets.openbao-harbor-reader-endeavour-secret-id.path;
      format = "docker";
      user = flakeConfig.username;
      authPath = "/run/user/1000/containers/auth.json";
    };

    environment.etc."libinput/local-overrides.quirks".text = ''
      [Positivo VAIO VJBK1BF11X Touchpad]
      MatchBus=i2c
      MatchVendor=0x093A
      MatchProduct=0x0255
      MatchUdevType=touchpad
      MatchDMIModalias=dmi:*:svnPositivoBahia-VAIO:pnVJBK1BF11X-*:*
      AttrEventCode=+BTN_RIGHT
    '';

    system.stateVersion = "25.11";
    nixpkgs.hostPlatform = "x86_64-linux";
    hardware.cpu.intel.updateMicrocode = true;
    boot = {
      kernelParams = ["nohibernate"];
      supportedFilesystems = ["ntfs"];
      loader = {
        efi.canTouchEfiVariables = true;
        grub = {
          device = "nodev";
          efiSupport = true;
          enable = true;
          configurationLimit = 3;
        };
        timeout = 1;
      };
    };
    services.btrfs.autoScrub.enable = true;
    nix.distributedBuildsOrion.enable = true;
    programs.appimage = {
      enable = true;
      binfmt = true;
    };
    programs.sccacheClient.enable = true;
    zramSwap = {
      enable = true;
      algorithm = "zstd";
      memoryPercent = 25;
    };
    modules.security.tor-monitor.enable = true;
    system.autoUpgrade.enable = false;
    services.openssh.enable = true;
    users.users.${flakeConfig.username}.openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHzKv0yi/MC6TpRB3w2BAGYJw1gELHQSJuna9r8d0j8/"
    ];
  };
}
