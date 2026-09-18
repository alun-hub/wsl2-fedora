#!/bin/bash
# Bygger den gyllene Amazon Linux-imagen och exporterar den till en
# WSL2-importbar rootfs-tarball. Kors pa en build-/CI-maskin med podman
# installerat - INTE pa utvecklarens Windows-dator. Systervariant till
# build-fedora-golden-image.sh.
#
# Anvandning:
#   ./build-amazonlinux-golden-image.sh [AL_VERSION] [DEV_USER] [OUTPUT_DIR]
#
# Exempel:
#   ./build-amazonlinux-golden-image.sh 2023 devuser ./dist
#
# Ombyggnadspolicy: kor detta vid Amazon Linux major-version-byten, inte
# for varje sakerhetspatch - de tacks av dnf-automatic inuti distrot. Vid
# en uppgradering: anvand upgrade-fedora-wsl.ps1 pa klienten (fungerar
# distro-agnostiskt), inte deploy-fedora-wsl.ps1 -Force, sa /home bevaras.
#
# Producerar:
#   <OUTPUT_DIR>/amazonlinux-golden-<AL_VERSION>-<DATE>.tar
#   <OUTPUT_DIR>/amazonlinux-golden-<AL_VERSION>-<DATE>.tar.sha256

set -euo pipefail

AL_VERSION="${1:-2023}"
DEV_USER="${2:-devuser}"
OUTPUT_DIR="${3:-./dist}"
BUILD_DATE="$(date +%Y.%m.%d)"
IMAGE_TAG="amazonlinux-golden:${AL_VERSION}-${BUILD_DATE}"
TAR_NAME="amazonlinux-golden-${AL_VERSION}-${BUILD_DATE}.tar"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTAINERFILE="${SCRIPT_DIR}/Containerfile.amazonlinux-golden"

if [[ ! -f "$CONTAINERFILE" ]]; then
  echo "FEL: hittar inte $CONTAINERFILE" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

echo "== Bygger $IMAGE_TAG (amazonlinux=$AL_VERSION, devuser=$DEV_USER) =="
podman build \
  --build-arg "AL_VERSION=${AL_VERSION}" \
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
