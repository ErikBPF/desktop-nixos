#!/usr/bin/env bash
# Harbor deploy/refresh on discovery. Idempotent: renders harbor.yml from the
# host .env, runs prepare (generates config + compose), brings the stack up.
#
# Normally driven DECLARATIVELY by the NixOS `harbor.service` oneshot
# (modules/hosts/discovery/harbor.nix), which sets HARBOR_INSTALLER_TGZ to a
# Nix-pinned installer and runs this as root on switch/boot. Can also be run by
# hand:  ssh -p 2222 erik@discovery 'bash .../scripts/harbor-setup.sh'
set -euo pipefail

# Run sudo only when not already root (the systemd service runs as root; a manual
# erik run needs sudo for prepare's root-owned config + the rootful compose).
SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"

# harbor.service (harbor.nix) injects HARBOR_VERSION + the pinned installer, so
# Nix is the single source of truth. The literal below is only the fallback for
# a bare manual run; verify the tag at github.com/goharbor/harbor/releases.
HARBOR_VERSION="${HARBOR_VERSION:-v2.15.2}"

DIR="$(cd "$(dirname "$0")/.." && pwd)"   # machines/discovery
RUNTIME_DIR="${HARBOR_RUNTIME_DIR:-$DIR}"
ENV_FILE="$RUNTIME_DIR/.env"
TMPL="$DIR/config/harbor/harbor.yml.tmpl"
INSTALLER_DIR="$RUNTIME_DIR/.harbor-installer"     # gitignored cache
HARBOR_DIR="$INSTALLER_DIR/harbor"
TARBALL="harbor-online-installer-${HARBOR_VERSION}.tgz"
URL="https://github.com/goharbor/harbor/releases/download/${HARBOR_VERSION}/${TARBALL}"
DATA_VOLUME="/home/erik/vault/harbor"

[ -f "$ENV_FILE" ] || { echo "❌ $ENV_FILE missing — run 'just push-env discovery' first"; exit 1; }
[ -f "$TMPL" ]     || { echo "❌ $TMPL missing"; exit 1; }

# Load only the Harbor-relevant vars (avoid sourcing the whole .env).
# HARBOR_ADMIN_PASSWORD + HARBOR_DB_PASSWORD come from OpenBao via the
# vault-agent render (/run/vault-agent/harbor.env, P3.3); fall back to the sops
# .env so a bare manual run (vault-agent down) still works during the transition.
# HOMELAB_DOMAIN is config — stays in .env, never migrated.
VAULT_ENV="/run/vault-agent/harbor.env"
HOMELAB_DOMAIN="$(grep -E '^HOMELAB_DOMAIN=' "$ENV_FILE" | cut -d= -f2-)"
HARBOR_SRC="$ENV_FILE"
[ -f "$VAULT_ENV" ] && HARBOR_SRC="$VAULT_ENV"
HARBOR_ADMIN_PASSWORD="$(grep -E '^HARBOR_ADMIN_PASSWORD=' "$HARBOR_SRC" | cut -d= -f2-)"
HARBOR_DB_PASSWORD="$(grep -E '^HARBOR_DB_PASSWORD=' "$HARBOR_SRC" | cut -d= -f2-)"
for v in HOMELAB_DOMAIN HARBOR_ADMIN_PASSWORD HARBOR_DB_PASSWORD; do
  [ -n "${!v}" ] || { echo "❌ $v not set (checked $VAULT_ENV then $ENV_FILE)"; exit 1; }
done

mkdir -p "$INSTALLER_DIR" "$DATA_VOLUME"

# Provision the installer once (cached). Prefer the Nix-pinned tarball
# (HARBOR_INSTALLER_TGZ, set by harbor.service) over a runtime fetch.
if [ ! -x "$HARBOR_DIR/install.sh" ]; then
  if [ -n "${HARBOR_INSTALLER_TGZ:-}" ] && [ -f "${HARBOR_INSTALLER_TGZ}" ]; then
    echo ":: using pinned installer ${HARBOR_INSTALLER_TGZ}"
    cp "$HARBOR_INSTALLER_TGZ" "$INSTALLER_DIR/$TARBALL"
  else
    echo ":: fetching Harbor ${HARBOR_VERSION} installer"
    curl -fL --retry 3 -o "$INSTALLER_DIR/$TARBALL" "$URL"
  fi
  # Guard: a wrong tag yields a tiny HTML error page that curl -f may not catch.
  if ! tar -tzf "$INSTALLER_DIR/$TARBALL" >/dev/null 2>&1; then
    echo "❌ not a valid tarball ($(wc -c < "$INSTALLER_DIR/$TARBALL") bytes) — verify HARBOR_VERSION=${HARBOR_VERSION} exists at github.com/goharbor/harbor/releases"
    rm -f "$INSTALLER_DIR/$TARBALL"; exit 1
  fi
  tar -xzf "$INSTALLER_DIR/$TARBALL" -C "$INSTALLER_DIR"
fi

# Render harbor.yml (substitute ONLY our three vars — pure bash, no envsubst
# dependency; safe for arbitrary values, leaves any other $ in the template).
echo ":: rendering harbor.yml"
content="$(cat "$TMPL")"
content="${content//'${HOMELAB_DOMAIN}'/$HOMELAB_DOMAIN}"
content="${content//'${HARBOR_ADMIN_PASSWORD}'/$HARBOR_ADMIN_PASSWORD}"
content="${content//'${HARBOR_DB_PASSWORD}'/$HARBOR_DB_PASSWORD}"
printf '%s\n' "$content" > "$HARBOR_DIR/harbor.yml"

cd "$HARBOR_DIR"
# Skip the expensive regen when nothing changed. `prepare` (a container run) +
# the sed rewrite docker-compose.yml every time, which makes `compose up` recreate
# all containers — a brief Harbor outage on EVERY unrelated discovery switch (the
# oneshot re-runs each switch/boot). Stamp the rendered harbor.yml + version and
# only re-prepare when it differs; `compose up -d` (cheap, idempotent) always runs
# so a stopped Harbor still comes back.
STAMP="$HARBOR_DIR/.harbor-setup.stamp"
new_stamp="$(printf '%s' "${content}${HARBOR_VERSION}" | sha256sum | cut -d' ' -f1)"
if [ -f docker-compose.yml ] && [ "$(cat "$STAMP" 2>/dev/null)" = "$new_stamp" ]; then
  echo ":: harbor.yml + version unchanged — skipping prepare/recreate"
else
  # The NixOS host has no /bin/bash, so `./install.sh`/`./prepare` shebangs fail;
  # run via `bash`. prepare renders ./common/config + docker-compose.yml (no
  # --with-trivy → Trivy omitted); its real work runs in the goharbor/prepare
  # container. Then prefix Harbor's generic container_names (redis/registry/
  # registryctl/nginx) with harbor- to avoid colliding with other stacks on the
  # shared docker host — only the docker name changes, the compose service name +
  # network alias stay, so Harbor's internal references are unaffected.
  echo ":: prepare (render config + compose, no Trivy)"
  $SUDO bash ./prepare
  $SUDO sed -i -E 's/^(    container_name: )(redis|registry|registryctl|nginx)$/\1harbor-\2/' docker-compose.yml
  printf '%s' "$new_stamp" | $SUDO tee "$STAMP" >/dev/null
fi
echo ":: bring up harbor"
$SUDO docker compose up -d

echo ":: harbor containers:"
$SUDO docker compose ps
echo ":: done — SWAG fronts https://harbor.${HOMELAB_DOMAIN} → host :8085"
echo ":: NEXT: create the Docker Hub proxy-cache project (see harbor-proxycache.sh / runbook)"
