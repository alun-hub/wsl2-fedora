# WSL2 + Podman + Distrobox — Fedora devmiljö (Windows 11)

Standardiserad, reproducerbar Fedora-devmiljö via Distrobox ovanpå Podman,
utan Microsoft Store. Verifierad end-to-end 2026-09-18 (GUI-passthrough
bekräftat fungerande med `xterm`).

## 1. Förutsättningar (engångsinstallation per maskin)

1. Aktivera Windows-funktioner (kräver omstart):
   ```powershell
   dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
   dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
   ```
2. Installera WSL-binären från GitHub Releases (INTE Microsoft Store):
   https://github.com/microsoft/WSL/releases — hämta senaste `.msi`/`.exe`
   från Assets (filtyp varierar mellan releaser, kolla alltid listan).
3. ```powershell
   wsl --set-default-version 2
   ```
4. Installera Podman CLI (INTE Podman Desktop) från
   https://github.com/containers/podman/releases
5. ```powershell
   podman machine init --cpus 2 --memory 2048 --disk-size 20
   ```
   Detta skapar WSL2-distrot `podman-machine-default` (minimal Fedora,
   rootless som standard).

   Om `ERROR_PATH_NOT_FOUND` vid init: kör `podman machine rm -f`, ta sedan
   manuellt bort kvarvarande mapp under
   `~/.local/share/containers/podman/machine/wsl/wsldist/` och kör om.

## 2. Engångsfixar inne i `podman-machine-default`

Denna minimala Fedora-image kör INTE riktig `systemd --user` (PID 1 är en
Podman-specifik bootstrap-wrapper, inte init). Det gör att
`loginctl enable-linger` inte fungerar och `/run/user/1000` saknas/är
oskrivbar vid boot → blockerar både `podman` och `distrobox`.

**Fix (workaround, inte en riktig systemd-lösning):** lägg till en
`[boot]`-sektion i `/etc/wsl.conf` inne i `podman-machine-default`
(skriv INTE över en ev. befintlig `[user]`-sektion):

```ini
[user]
default=user

[boot]
command = "mkdir -p /run/user/1000 && chown 1000:1000 /run/user/1000 && chmod 700 /run/user/1000"
```

Detta körs som root vid varje WSL-boot oavsett systemd-status. **Verifierat
2026-09-18** att detta håller efter en riktig `wsl --shutdown` + omstart —
`/run/user/1000` finns med rätt ägare/rättigheter och `podman info` /
`distrobox list` går igenom utan permission-fel.

## 3. GUI-stöd (WSLg)

WSLg-socklar finns automatiskt under `/mnt/wslg` i `podman-machine-default`.
Miljövariablerna sätts INTE automatiskt av denna minimala image — lägg i
`~/.bashrc` (eller motsvarande) om du vill ha dem i skalet direkt:

```sh
export DISPLAY=:0
export WAYLAND_DISPLAY=wayland-0
export XDG_RUNTIME_DIR=/mnt/wslg/runtime-dir
export PULSE_SERVER=/mnt/wslg/PulseServer
```

**Viktigt:** kör ALDRIG `wsl -d podman-machine-default` från en förhöjd
(Admin) terminal när GUI-appar ska visas — det tvingar WSLg:s RDP-koppling
till "[WARN:COPY MODE]" (trasig/statisk rendering). Kör alltid från en
vanlig användarterminal.

Liten font i X11-appar = DPI-mismatch. Fix: `Xft.dpi` i `~/.Xresources`,
eller `GDK_SCALE`/`QT_SCALE_FACTOR` för GTK/Qt-appar.

## 4. Skapa en Distrobox-box (repeterbart, per box)

**Känt problem:** `distrobox create` med sina defaults ger en container
som `crun` inte kan starta:

```
Error: unable to start container "...": crun: cannot open sd-bus: No such file or directory
```

Orsak: containern skapas med per-container cgroup-manager `systemd`, vilket
kräver D-Bus-delegation — men `dbus-daemon` är inte installerat på detta
minimala host-system. Ett andra lager av samma problem visar sig som:

```
Error: using --follow with the journald --log-driver but without the
journald --events-backend (file) is not supported
```

eftersom journald inte heller körs på denna host.

**Fix:** tvinga `cgroupfs` och `k8s-file` explicit vid `create` (se
`provision-fedora-box.sh` nedan för ett komplett, körbart skript):

```bash
distrobox create --image fedora:latest --name fedora-box \
  --additional-flags "--cgroup-manager cgroupfs --log-driver k8s-file" -Y
```

Verifiera:

```bash
podman inspect fedora-box --format 'Cgroup={{.HostConfig.CgroupManager}} LogDriver={{.HostConfig.LogConfig.Type}}'
# Ska visa: Cgroup=cgroupfs LogDriver=k8s-file
```

## 5. Använda boxen

```bash
distrobox enter fedora-box
```

GUI-passthrough är **bekräftat fungerande** — `sudo dnf install -y xterm`
och `xterm` inne i boxen öppnar ett riktigt fönster på Windows-skrivbordet
via WSLg.

## 6. Driftsnotiser / gotchas att komma ihåg

- Om en container fastnar i `Stopping`-state och varken `podman stop` eller
  `podman rm -f` biter (klassiskt rootless-podman-på-WSL2-kvirk): kör
  `wsl --shutdown`, vänta tills alla distron visar `Stopped` i
  `wsl -l -v`, starta om `podman-machine-default` — det nollställer
  container-states utan att röra config (wsl.conf-fixen och skapade boxar
  finns kvar).
- Kör aldrig `wsl -d podman-machine-default` som Administratör om GUI ska
  fungera (se avsnitt 3).
- Att köra kommandon mot WSL via `wsl -d ... -- bash -c "..."` från en
  Windows-mappad arbetskatalog ger ofta en ofarlig varningsrad
  (`chdir(...) failed 2`) — det är bara WSL som inte kan mappa Windows-cwd
  till en Linux-path, inget att åtgärda.
- Nästlad citat-hantering PowerShell → `wsl.exe` → `bash -c` är opålitlig
  för komplexa kommandon (radbrytningar, citattecken försvinner eller
  dupliceras). Skriv riktiga skriptfiler och kör dem istället för långa
  inline one-liners.

## 7. Nästa steg (ej gjort ännu)

- Standardisera detta som en onboarding-guide för teamets övriga
  utvecklare (detta dokument + `provision-fedora-box.sh` är en bra grund).
- Överväg om `dbus-daemon` bör installeras på `podman-machine-default` som
  ett alternativ till `cgroupfs`-workarounden, ifall framtida
  systemd-beroende funktionalitet behövs (avfärdat 2026-09-18 till förmån
  för den enklare cgroupfs-lösningen).
