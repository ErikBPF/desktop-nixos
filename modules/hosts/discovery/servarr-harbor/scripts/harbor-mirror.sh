#!/usr/bin/env bash
# Mirror a published OSS image from GHCR (public) into the homelab Harbor
# registry (the private image SSOT — D7/D9 publish-and-pin). kindle-dash is
# built + pushed to GHCR by its own repo's CI on a version tag; this step
# copies that exact artifact into Harbor so homelab consumers (servarr) pin a
# Harbor digest instead of reaching out to GHCR at deploy time.
#
# GitHub's public runners can't reach the LAN-only Harbor, so this runs from a
# host that reaches BOTH registries (the workstation, or discovery itself).
#
#   # creds: a Harbor robot scoped to push the public `library` project.
#   export HARBOR_ROBOT_USER='robot$library+mirror'
#   export HARBOR_ROBOT_SECRET='...'            # from sops: HARBOR_MIRROR_SECRET
#   ./harbor-mirror.sh v0.2.0 sha256:<published-digest>
#
# Verifies the source signature and tag, copies by digest with skopeo, and
# fails unless Harbor preserves the exact published digest.
set -euo pipefail

VERSION="${1:?usage: harbor-mirror.sh <version, e.g. v0.2.0> <sha256:digest>}"
EXPECTED_DIGEST="${2:?usage: harbor-mirror.sh <version, e.g. v0.2.0> <sha256:digest>}"
[[ "${VERSION}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "invalid version: ${VERSION}" >&2
  exit 1
}
[[ "${EXPECTED_DIGEST}" =~ ^sha256:[0-9a-f]{64}$ ]] || {
  echo "invalid digest: ${EXPECTED_DIGEST}" >&2
  exit 1
}

SRC_IMAGE="${SRC_IMAGE:-ghcr.io/erikbpf/kindle-dash}"
HARBOR_REGISTRY="${HARBOR_REGISTRY:-harbor.homelab.pastelariadev.com}"
DST_IMAGE="${DST_IMAGE:-${HARBOR_REGISTRY}/library/kindle-dash}"

ROBOT_USER="${HARBOR_ROBOT_USER:?set HARBOR_ROBOT_USER (Harbor robot with push on library)}"
ROBOT_SECRET="${HARBOR_ROBOT_SECRET:?set HARBOR_ROBOT_SECRET}"

src_tag="${SRC_IMAGE}:${VERSION}"
src="${SRC_IMAGE}@${EXPECTED_DIGEST}"
dst="${DST_IMAGE}:${VERSION}"

echo ":: mirroring ${src} -> ${dst}"

if command -v skopeo >/dev/null 2>&1; then
  command -v cosign >/dev/null 2>&1 || {
    echo "cosign is required to verify the published image" >&2
    exit 1
  }
  cosign verify \
    --certificate-identity-regexp '^https://github\.com/ErikBPF/kindle-dash/\.github/workflows/publish\.yml@refs/heads/main$' \
    --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' \
    "${src}" >/dev/null
  tag_digest="$(skopeo inspect --format '{{.Digest}}' "docker://${src_tag}")"
  [[ "${tag_digest}" == "${EXPECTED_DIGEST}" ]] || {
    echo "tag digest mismatch: ${src_tag} resolves to ${tag_digest}" >&2
    exit 1
  }
  skopeo --insecure-policy copy --all --preserve-digests --retry-times 3 \
    --dest-creds "${ROBOT_USER}:${ROBOT_SECRET}" \
    "docker://${src}" "docker://${dst}"
  src_digest="$(skopeo inspect --format '{{.Digest}}' "docker://${src}")"
  dst_digest="$(skopeo inspect --creds "${ROBOT_USER}:${ROBOT_SECRET}" \
    --format '{{.Digest}}' "docker://${dst}")"
  [[ "${src_digest}" == "${EXPECTED_DIGEST}" ]] || {
    echo "source digest mismatch: expected ${EXPECTED_DIGEST}, got ${src_digest}" >&2
    exit 1
  }
  [[ "${dst_digest}" == "${EXPECTED_DIGEST}" ]] || {
    echo "mirror digest mismatch: expected ${EXPECTED_DIGEST}, got ${dst_digest}" >&2
    exit 1
  }
  printf ':: digest parity verified: %s\n' "${EXPECTED_DIGEST}"
else
  echo "skopeo is required for digest-preserving promotion" >&2
  exit 1
fi

echo ":: mirror complete — pin consumers to ${dst}@${EXPECTED_DIGEST}"
