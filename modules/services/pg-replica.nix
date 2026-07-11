# NetBird Postgres read-replica (R3, docs/proposals/
# 2026-07-10-vanguard-second-oracle-node.md; NetBird overlay design
# docs/proposals/2026-07-10-netbird-selfhosted-overlay.md §4a/§7). A streaming
# replica of discovery's NetBird-DB Postgres turns DR restore from "restore a
# snapshot" into "promote a warm replica" — RTO shrinks from hours to minutes,
# well under the 7-day credentialsTTL survival window. shared_buffers is tuned
# tiny because this shares a 1 GB host with vanguard's other roles.
#
# NOT a turnkey replica. NixOS declares postgresql.conf settings, but the two
# steps that actually make this a replica are manual, one-time, and happen
# AFTER enabling this and BEFORE starting postgresql.service — neither is
# automated here (proposal §R3/§7, NetBird RFC §10 phase 6 DR drill):
#   1. Seed the data directory from a base backup of discovery's primary
#      (`pg_basebackup`), then drop the PG16+ `standby.signal` marker in it.
#   2. Populate postgres's ~/.pgpass from the sops secret below — the
#      replication password is deliberately NOT embedded in primary_conninfo
#      (that would put a secret in the Nix store); libpq reads it from
#      .pgpass instead.
#
# DISABLED BY DEFAULT (services.pgReplica.enable = false).
{
  self,
  config,
  ...
}: let
  discoveryTailnetIp = config.flake.fleet.hosts.discovery.tailscaleIp;
in {
  flake.modules.nixos.pg-replica = {
    config,
    lib,
    ...
  }: let
    cfg = config.services.pgReplica;
    sopsFile = self + "/secrets/sops/secrets.yaml";
  in {
    options.services.pgReplica = {
      enable = lib.mkEnableOption "the NetBird Postgres streaming read-replica — disabled by default, see docs/proposals/2026-07-10-vanguard-second-oracle-node.md §R3";

      primaryHost = lib.mkOption {
        type = lib.types.singleLineStr;
        default = discoveryTailnetIp;
        description = "Primary Postgres host (discovery), reached over the tailnet.";
      };

      primaryPort = lib.mkOption {
        type = lib.types.port;
        default = 5432;
        description = "Primary Postgres port.";
      };

      replicationUser = lib.mkOption {
        type = lib.types.singleLineStr;
        default = "replicator";
        description = "Replication role used for the streaming connection.";
      };

      sharedBuffers = lib.mkOption {
        type = lib.types.singleLineStr;
        default = "64MB";
        description = "shared_buffers — kept tiny; vanguard's total RAM is 1 GB, shared with the other roles.";
      };
    };

    config = lib.mkIf cfg.enable {
      services.postgresql = {
        enable = true;
        settings = {
          hot_standby = "on";
          shared_buffers = cfg.sharedBuffers;
          # No password here on purpose (see file header) — libpq falls back
          # to postgres's ~/.pgpass, populated from the sops secret below.
          primary_conninfo = "host=${cfg.primaryHost} port=${toString cfg.primaryPort} user=${cfg.replicationUser} application_name=vanguard sslmode=prefer";
        };
      };

      # TODO(before enable): this key does not exist in secrets/sops/secrets.yaml
      # yet — add the replication role's password before flipping this role on,
      # same placeholder pattern as netbird/auth_secret (modules/hosts/voyager/
      # netbird-relay.nix). Once decryptable, render it into postgres's
      # ~/.pgpass (`hostname:port:database:user:password`) as a one-time manual
      # step alongside the pg_basebackup seed (file header, step 2) — not
      # automated here, since .pgpass must be created after pg_basebackup
      # populates the data directory anyway.
      sops.secrets."pg-replica/replication_password" = {
        inherit sopsFile;
        format = "yaml";
        key = "pg-replica/replication_password";
        mode = "0400";
        owner = "postgres";
      };
    };
  };
}
