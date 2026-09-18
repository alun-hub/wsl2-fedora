#!/bin/bash
# Repeterbart provisioning-skript för en Distrobox-baserad Fedora-devmiljö
# ovanpå podman-machine-default (Podman på WSL2, Windows 11).
#
# Kör INNE I podman-machine-default (t.ex. via:
#   wsl -d podman-machine-default -- bash -lc /path/to/provision-fedora-box.sh
# ), aldrig från en förhöjd (Admin) Windows-terminal.
#
# Förutsätter att steg 1-3 i README-distrobox-wsl2-podman.md redan är gjorda
# (WSL2, Podman CLI, podman machine init, /etc/wsl.conf [boot]-fix).

set -euo pipefail

BOX_NAME="${1:-fedora-box}"
IMAGE="${2:-fedora:latest}"

echo "== Provisioning distrobox '$BOX_NAME' from image '$IMAGE' =="

if distrobox list 2>/dev/null | grep -q "$BOX_NAME"; then
  echo "-- Box '$BOX_NAME' finns redan, tar bort den forst --"
  podman rm -f "$BOX_NAME" 2>/dev/null || true
fi

# --cgroup-manager cgroupfs: undviker "crun: cannot open sd-bus" (ingen
#   dbus-daemon pa denna minimala host).
# --log-driver k8s-file: undviker "--follow with journald --log-driver
#   ... not supported" (ingen journald pa denna minimala host).
distrobox create \
  --image "$IMAGE" \
  --name "$BOX_NAME" \
  --additional-flags "--cgroup-manager cgroupfs --log-driver k8s-file" \
  -Y

echo "-- Verifierar konfiguration --"
podman inspect "$BOX_NAME" --format 'Cgroup={{.HostConfig.CgroupManager}} LogDriver={{.HostConfig.LogConfig.Type}}'

echo "-- Testar att boxen startar och GUI-env forwardas --"
distrobox enter "$BOX_NAME" -- bash -c '
  echo "DISPLAY=$DISPLAY"
  echo "WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
  echo "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"
  ls -la /tmp/.X11-unix 2>&1 || echo "VARNING: /tmp/.X11-unix saknas"
'

echo "== Klart. Ga in i boxen med: distrobox enter $BOX_NAME =="
echo "== For att testa GUI: distrobox enter $BOX_NAME -- bash -c 'sudo dnf install -y xterm && xterm' =="
