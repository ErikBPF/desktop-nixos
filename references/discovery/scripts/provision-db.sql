-- =============================================================================
-- scripts/provision-db.sql — Discovery database provisioning
-- Machine: Discovery (Debian — 24/7 Infrastructure)
--
-- Creates databases needed by Discovery application stacks.
-- Mounted as /docker-entrypoint-initdb.d/provision.sql in infra.yml.
-- Runs automatically on first Postgres start only.
-- Safe to re-run manually: just db-shell -> \i /scripts/provision-db.sql
-- =============================================================================

\set ON_ERROR_STOP off

-- Homepage dashboard
SELECT 'CREATE DATABASE homepage'      WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'homepage')\gexec

-- Monitoring
SELECT 'CREATE DATABASE healthchecks'  WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'healthchecks')\gexec

-- AI gateway
SELECT 'CREATE DATABASE litellm'       WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'litellm')\gexec

-- AI observability (Langfuse)
SELECT 'CREATE DATABASE langfuse'      WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'langfuse')\gexec

-- *arr apps (two DBs each: main + log)
SELECT 'CREATE DATABASE sonarr_main'   WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'sonarr_main')\gexec
SELECT 'CREATE DATABASE sonarr_log'    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'sonarr_log')\gexec
SELECT 'CREATE DATABASE radarr_main'   WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'radarr_main')\gexec
SELECT 'CREATE DATABASE radarr_log'    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'radarr_log')\gexec
SELECT 'CREATE DATABASE lidarr_main'   WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'lidarr_main')\gexec
SELECT 'CREATE DATABASE lidarr_log'    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'lidarr_log')\gexec
SELECT 'CREATE DATABASE prowlarr_main' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'prowlarr_main')\gexec
SELECT 'CREATE DATABASE prowlarr_log'  WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'prowlarr_log')\gexec

-- Media
SELECT 'CREATE DATABASE jellystat'     WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'jellystat')\gexec
SELECT 'CREATE DATABASE seerr'         WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'seerr')\gexec

-- Download automation
SELECT 'CREATE DATABASE autobrr'       WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'autobrr')\gexec

\set ON_ERROR_STOP on
