# Declarative Harbor on discovery (RFC 2026-06-22-harbor-declarative.md, oneshot
# variant). Harbor ships no static compose — its `prepare` step generates the
# compose + per-component config in-place with the ownership each container
# needs. Rather than vendor that derived output into git (which flips ownership
# to the deploy user and breaks rsyslog/registry — see the RFC), we keep
# `prepare` as the reproducible build step and make it DECLARATIVE:
#   • the installer is Nix-pinned (fetchurl, hashed) — no runtime curl;
#   • harbor.yml is rendered from the host .env (servarr .env.sops);
#   • a systemd oneshot runs prepare + compose-up on every switch/boot,
#     reconciling Harbor to the committed inputs.
# The setup logic lives in the servarr repo (scripts/harbor-setup.sh, pulled by
# servarr-pull) so a Harbor config change is a servarr commit, not a host edit.
{config, ...}: let
  inherit (config) username;
in {
  flake.modules.nixos.discovery-harbor = {pkgs, ...}: let
    # Keep in sync with HARBOR_VERSION in scripts/harbor-setup.sh.
    harborVersion = "v2.14.4";
    harborInstaller = pkgs.fetchurl {
      url = "https://github.com/goharbor/harbor/releases/download/${harborVersion}/harbor-online-installer-${harborVersion}.tgz";
      sha256 = "1hc77c6ad25xipncppjy80ljw9gi3840499b8yr569vf45zs4ddz";
    };
    setup = "/home/${username}/servarr/machines/discovery/scripts/harbor-setup.sh";
  in {
    systemd.services.harbor = {
      description = "Harbor registry — declarative prepare + compose up (pinned installer)";
      # Needs docker up and egress (prepare/compose pull images on a fresh host).
      after = ["docker.service" "network-online.target"];
      requires = ["docker.service"];
      wants = ["network-online.target"];
      wantedBy = ["multi-user.target"];
      # Tools harbor-setup.sh + Harbor's `prepare` wrapper shell out to (runs as
      # root → $SUDO is a no-op). prepare needs awk/openssl/hostname/getent etc.
      path = with pkgs; [
        docker
        docker-compose
        bash
        coreutils
        gnutar
        gzip
        gnused
        gnugrep
        gawk
        findutils
        hostname
        openssl
        util-linux
        glibc.bin # getent
        curl
      ];
      # Single-source the version + pinned tarball to the script (Nix owns it;
      # the script's HARBOR_VERSION default is only the bare manual-run fallback).
      environment = {
        HARBOR_INSTALLER_TGZ = harborInstaller;
        HARBOR_VERSION = harborVersion;
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.bash}/bin/bash ${setup}";
        # servarr-pull (a user service) drops the decrypted .env; if it isn't
        # there yet on first boot, harbor-setup.sh exits non-zero → retry.
        Restart = "on-failure";
        RestartSec = "30s";
      };
      # Retry indefinitely until .env is present (no start-limit burn-out).
      startLimitIntervalSec = 0;
    };
  };
}
