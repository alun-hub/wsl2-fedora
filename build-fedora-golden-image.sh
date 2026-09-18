#!/bin/bash
# Bygger den gyllene Fedora-imagen och exporterar den till en WSL2-import-
# bar rootfs-tarball. Kors pa en build-/CI-maskin med podman installerat -
# INTE pa utvecklarens Windows-dator.
#
# Anvandning:
#   ./build-fedora-golden-image.sh [FEDORA_VERSION] [DEV_USER] [OUTPUT_DIR]
#
# Exempel:
#   ./build-fedora-golden-image.sh 44 devuser ./dist
#
# Ombyggnadspolicy: kor detta vid Fedora major-version-byten (t.ex. 41 -> 44),
# inte for varje sakerhetspatch - de tacks av dnf-automatic inuti distrot.
# Vid en uppgradering: anvand upgrade-fedora-wsl.ps1 pa klienten, inte
# deploy-fedora-wsl.ps1 -Force, sa /home bevaras.
#
# Producerar:
#   <OUTPUT_DIR>/fedora-golden-<FEDORA_VERSION>-<DATE>.tar
#   <OUTPUT_DIR>/fedora-golden-<FEDORA_VERSION>-<DATE>.tar.sha256

set -euo pipefail

FEDORA_VERSION="${1:-44}"
DEV_USER="${2:-devuser}"
OUTPUT_DIR="${3:-./dist}"
BUILD_DATE="$(date +%Y.%m.%d)"
IMAGE_TAG="fedora-golden:${FEDORA_VERSION}-${BUILD_DATE}"
TAR_NAME="fedora-golden-${FEDORA_VERSION}-${BUILD_DATE}.tar"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINERFILE="${SCRIPT_DIR}/Containerfile.fedora-golden"

if [[ ! -f "$CONTAINERFILE" ]]; then
  echo "FEL: hittar inte $CONTAINERFILE" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

echo "== Bygger $IMAGE_TAG (fedora=$FEDORA_VERSION, devuser=$DEV_USER) =="
podman build \
  --build-arg "FEDORA_VERSION=${FEDORA_VERSION}" \
  --build-arg "DEV_USER=${DEV_USER}" \
  -t "$IMAGE_TAG" \
  -f "$CONTAINERFILE" \
  "$SCRIPT_DIR"

echo "== Exporterar rootfs till tarball =="
CID=$(podman create "$IMAGE_TAG")
trap 'podman rm -f "$CID" >/dev/null 2>&1 || true' EXIT

podman export "$CID" -o "${OUTPUT_DIR}/${TAR_NAME}"

echo "== Genererar checksumma =="
( cd "$OUTPUT_DIR" && sha256sum "$TAR_NAME" > "${TAR_NAME}.sha256" )

echo "== Snabb sanity-check av tarball-innehall =="
tar -tf "${OUTPUT_DIR}/${TAR_NAME}" | grep -E '^(etc/wsl\.conf|etc/passwd|usr/lib/systemd/systemd)$' \
  && echo "OK: wsl.conf, passwd och systemd finns i imagen" \
  || { echo "VARNING: forvantade filer saknas i tarballen - granska bygget"; exit 1; }

echo
echo "== Klart =="
echo "Tarball:   ${OUTPUT_DIR}/${TAR_NAME}"
echo "Checksum:  ${OUTPUT_DIR}/${TAR_NAME}.sha256"
echo
echo "Lagg tarballen + checksumman pa er interna fileshare/artefaktlager och"
echo "referera den fran deploy-fedora-wsl.ps1 (-ImagePath) pa klientsidan."
