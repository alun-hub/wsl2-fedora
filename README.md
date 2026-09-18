# wsl2-fedora

Byggskript för att ge Windows 11-utvecklare en riktig Fedora-devmiljö via
WSL2 - utan Microsoft Store, och utan att förlora `/home` vid uppgraderingar.

## Rekommenderad väg: gyllene Fedora-WSL2-image

En "golden image"-pipeline: en [Containerfile](Containerfile.fedora-golden)
byggs centralt till en WSL2-importbar rootfs-tarball, som paketeringsteamet
sedan rullar ut tyst på varje dator. Ingen `podman machine`, ingen
Distrobox - WSL2 har numera nativt `systemd`-stöd, så importerad distro
**är** en riktig Fedora rakt av.

Validerad end-to-end 2026-09-18 (Fedora 44): `systemd`, rootless `podman`
och GUI-passthrough (WSLg) fungerar direkt ur en ren `wsl --import`, utan
manuell efterkonfiguration.

| Fil | Körs var | Syfte |
|---|---|---|
| [Containerfile.fedora-golden](Containerfile.fedora-golden) | Build-maskin | Definierar imagen: baseline-paket, devanvändare, `systemd=true`, kända bootfixar |
| [build-fedora-golden-image.sh](build-fedora-golden-image.sh) | Build-maskin (med podman) | Bygger imagen, exporterar rootfs-tarball + sha256 |
| [deploy-fedora-wsl.ps1](deploy-fedora-wsl.ps1) | Klientdator (paketeringsteam) | Förstagångsinstallation: WSL2 + `wsl --import`, idempotent, MDM-vänliga exitkoder |
| [upgrade-fedora-wsl.ps1](upgrade-fedora-wsl.ps1) | Klientdator (paketeringsteam) | Uppgraderar till ny image vid Fedora major-version-byte, **bevarar `/home`** |
| [fix-home-ownership.sh](fix-home-ownership.sh) | Körs av upgrade-scriptet | Rättar ägarskap i `/home` efter återställning |

### Snabbstart

```bash
# På en build-maskin med podman:
./build-fedora-golden-image.sh 44 devuser ./dist
```

```powershell
# På klientdatorn (som Administrator), första gången:
.\deploy-fedora-wsl.ps1 -MsiPath \\fileshare\wsl\Wsl.msi `
  -ImagePath \\fileshare\wsl\fedora-golden-44-2026.09.18.tar

# Vid en senare major-version-uppgradering (behåller /home):
.\upgrade-fedora-wsl.ps1 -NewImagePath \\fileshare\wsl\fedora-golden-45-....tar
```

Ombyggnadspolicy: imagen byggs om vid Fedora major-version-byten, inte för
varje säkerhetspatch - de täcks av `dnf5-automatic.timer` som körs
kontinuerligt inuti den redan utrullade distrot.

### Kända gotchas (redan åtgärdade i Containerfile.fedora-golden)

- Fedora 44 kör `dnf5` - rätt timer-enhet är `dnf5-automatic.timer`, inte
  `dnf-automatic-install.timer`.
- `newuidmap`/`newgidmap` tappar sin setuid-bit under ett rootless
  `podman build` (RPM:ets `%post`-scriptlet lyckas inte sätta den i den
  kontexten), vilket blockerar rootless `podman` i den färdiga distrot.
  Åtgärdat via en `[boot] command` i `/etc/wsl.conf` som återapplicerar
  biten på varje boot, oavsett grundorsak.

## För utvecklaren som ska använda miljön

[DEVELOPER-GUIDE.md](DEVELOPER-GUIDE.md) - hur man öppnar Fedora-miljön,
var man ska spara sina filer, GUI-program, Podman, VS Code-integration och
vanliga frågor. Länka/dela den här filen med utvecklarna, inte den här
README:n som är riktad mot build-/paketeringsteamet.

## Licens

[MIT](LICENSE)
