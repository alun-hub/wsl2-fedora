# wsl2-fedora

En reproducerbar Fedora-utvecklingsmiljö för Windows 11-datorer, levererad
via WSL2 - helt utan Microsoft Store. En "gyllene image" byggs en gång
centralt och rullas sedan ut tyst till valfritt antal utvecklardatorer.

Miljön är en enda WSL2-distro med riktig `systemd` aktiverat. Det du får
när du öppnar den ÄR Fedora, rakt av - inget extra virtualiseringslager,
ingen ytterligare container ovanpå.

## Tre roller i det här flödet

1. **Byggmaskinen** - en valfri maskin (behöver inte vara Windows) med ett
   containerverktyg (`podman`) installerat. Bygger den gyllene imagen en
   gång per Fedora-version.
2. **Paketeringsteamet** - kör installations-/uppgraderingsskripten mot
   varje utvecklares Windows 11-dator.
3. **Utvecklaren** - använder den färdiga Fedora-miljön dagligen. Se
   [DEVELOPER-GUIDE.md](DEVELOPER-GUIDE.md).

**Podman behövs INTE på utvecklarens Windows-dator.** Det behövs bara på
byggmaskinen (för att skapa imagen) och finns redan förinstallerat inuti
den färdiga Fedora-miljön (för utvecklarens eget containerarbete).

## Filer i det här repot

| Fil | Beskrivning |
|---|---|
| [Containerfile.fedora-golden](Containerfile.fedora-golden) | Definierar innehållet i Fedora-imagen |
| [build-fedora-golden-image.sh](build-fedora-golden-image.sh) | Bygger imagen och paketerar den till en WSL2-importbar fil |
| [deploy-fedora-wsl.ps1](deploy-fedora-wsl.ps1) | Installerar WSL2 och Fedora-miljön på en ny dator |
| [upgrade-fedora-wsl.ps1](upgrade-fedora-wsl.ps1) | Uppgraderar en befintlig installation till en nyare Fedora-version utan att förlora data |
| [fix-home-ownership.sh](fix-home-ownership.sh) | Hjälpskript som `upgrade-fedora-wsl.ps1` kör internt |
| [DEVELOPER-GUIDE.md](DEVELOPER-GUIDE.md) | Instruktioner för utvecklaren som ska ANVÄNDA miljön dagligen |
| [LICENSE](LICENSE) | MIT-licens |

---

## Steg 1: Bygg den gyllene imagen

Görs en gång centralt - inte på varje utvecklares dator.

### Förutsättningar på byggmaskinen

- En maskin (fysisk, virtuell, eller en WSL2-distro på Windows - valfritt)
  med `podman` installerat:
  - Fedora/RHEL/CentOS: `sudo dnf install -y podman`
  - Debian/Ubuntu: `sudo apt install -y podman`
  - Övriga plattformar: se https://podman.io/docs/installation
- Det här repot nedladdat till byggmaskinen:
  ```bash
  git clone https://github.com/alun-hub/wsl2-fedora.git
  cd wsl2-fedora
  ```

### Kör bygget

```bash
./build-fedora-golden-image.sh 44 devuser ./dist
```

Parametrarna, i tur och ordning (alla är valfria - utan argument används
värdena nedan som default):

| Parameter | Exempel | Betyder |
|---|---|---|
| 1 | `44` | Vilken Fedora-major-version som ska byggas |
| 2 | `devuser` | Användarnamnet som skapas inuti Fedora-miljön |
| 3 | `./dist` | Var de färdiga filerna ska hamna |

### Vad skriptet gör

1. Bygger imagen från `Containerfile.fedora-golden` med `podman build`.
2. Skapar en tillfällig container från den byggda imagen och exporterar
   dess filsystem till en tarball med `podman export`.
3. Genererar en sha256-checksumma för tarballen.
4. Gör en sanity-check att `/etc/wsl.conf`, `/etc/passwd` och `systemd`
   faktiskt finns med i den färdiga tarballen - avslutar med felkod om
   något saknas.

### Förväntat resultat

Bygget tar normalt 5-15 minuter (mest tid går åt att ladda ner
Fedora-paket). Efteråt finns två filer i `./dist/`:

```
dist/fedora-golden-44-2026.09.18.tar        <- sjalva imagen, ca 1 GB
dist/fedora-golden-44-2026.09.18.tar.sha256 <- checksumma
```

Lägg dessa två filer på en intern fileshare eller ett artefaktlager som
paketeringsteamets Windows-datorer kan nå, t.ex. `\\fileshare\wsl\`.

---

## Steg 2: Installera på en utvecklares dator (första gången)

Körs av paketeringsteamet, en gång per dator.

### Förutsättningar

- Datorn kör Windows 11.
- Du har administratörsrättigheter på datorn (krävs för att aktivera
  Windows-funktioner).
- Du har laddat ner den fristående WSL-installeraren - **INTE via
  Microsoft Store** - från https://github.com/microsoft/WSL/releases:
  öppna senaste releasen och hämta `.msi`- eller `.exe`-filen under
  Assets (filtypen varierar mellan versioner - kontrollera alltid listan
  på sidan istället för att gissa filnamnet).
- Du har `fedora-golden-*.tar` och dess `.sha256`-fil från Steg 1
  tillgängliga, t.ex. via en fileshare.
- Du har `deploy-fedora-wsl.ps1` från det här repot tillgängligt på
  datorn.

### Kör installationen

Öppna PowerShell **som Administratör** och kör:

```powershell
.\deploy-fedora-wsl.ps1 `
  -MsiPath "C:\Installers\Wsl.msi" `
  -ImagePath "\\fileshare\wsl\fedora-golden-44-2026.09.18.tar"
```

Byt ut sökvägarna mot var din WSL-installerare respektive image faktiskt
ligger.

Alla parametrar:

| Parameter | Krävs | Default | Betyder |
|---|---|---|---|
| `-MsiPath` | Endast om WSL inte redan är installerat | - | Sökväg till den fristående WSL-installeraren |
| `-ImagePath` | Ja | - | Sökväg till `fedora-golden-*.tar` |
| `-ChecksumPath` | Nej | `<ImagePath>.sha256` | Sökväg till checksumfilen |
| `-DistroName` | Nej | `FedoraDev` | Namnet WSL-distrot får |
| `-InstallLocation` | Nej | `C:\WSL\FedoraDev` | Var distrots VHDX-fil lagras |
| `-Force` | Nej | Av | Tar bort och återskapar distrot om den redan finns - **all data i distrot förloras, se varning nedan** |

### Vad skriptet gör, steg för steg

1. Kontrollerar att Windows-funktionerna `Microsoft-Windows-Subsystem-Linux`
   och `VirtualMachinePlatform` är aktiverade - aktiverar dem annars.
   **Om detta var första gången de aktiverades krävs en omstart.** Skriptet
   avslutar då med kod `3010` och skriver ut att du ska köra om kommandot
   efter omstart. Starta om datorn och kör exakt samma kommando igen.
2. Kontrollerar om WSL redan är installerat (`wsl --status`). Om inte,
   installerar det tyst från `-MsiPath`.
3. Sätter WSL:s standardversion till 2.
4. Verifierar `-ImagePath` mot dess `.sha256`-fil. Avbryter om
   checksumman inte stämmer.
5. Importerar imagen som en ny WSL-distro till `-InstallLocation`.
6. Startar distrot en första gång och kör `systemctl is-system-running`
   för att verifiera att `systemd` faktiskt kom upp korrekt.
7. Skriver en logg till `C:\ProgramData\FedoraWSLDeploy\deploy-<tidsstämpel>.log`.

### Förväntat resultat

Skriptet avslutar med:

```
== Klart: 'FedoraDev' ar redo. Utvecklaren startar med: wsl -d FedoraDev ==
```

och avslutningskod `0`. Utvecklaren kan nu öppna en terminal och köra:

```powershell
wsl -d FedoraDev
```

Skicka [DEVELOPER-GUIDE.md](DEVELOPER-GUIDE.md) till utvecklaren.

### Om något går fel

- Avslutningskod `1` = fel. Se loggfilen i `C:\ProgramData\FedoraWSLDeploy\`
  för detaljer.
- Avslutningskod `3010` = lyckades hittills men kräver en omstart - kör om
  exakt samma kommando efter omstart.
- Körs skriptet igen efter att distrot redan finns hoppar det över
  importsteget (idempotent) om du inte anger `-Force`.
- **`-Force` tar bort och återskapar distrot från grunden - all data i
  distrot, inklusive `/home`, går förlorad.** Använd inte detta på en
  dator med befintligt utvecklararbete - se Steg 3 istället.

---

## Steg 3: Uppgradera en befintlig installation (vid Fedora major-version-byte)

Körs av paketeringsteamet när en ny gyllene image (t.ex. Fedora 45) har
byggts enligt Steg 1, och datorn redan har en fungerande installation från
Steg 2 vars data INTE ska förloras.

**Kör inte Steg 2 med `-Force` för detta - det bevarar inte `/home`.**
Använd istället:

```powershell
.\upgrade-fedora-wsl.ps1 -NewImagePath "\\fileshare\wsl\fedora-golden-45-2026.12.01.tar"
```

Alla parametrar:

| Parameter | Krävs | Default | Betyder |
|---|---|---|---|
| `-NewImagePath` | Ja | - | Sökväg till den nya `fedora-golden-*.tar` |
| `-ChecksumPath` | Nej | `<NewImagePath>.sha256` | Sökväg till checksumfilen |
| `-DistroName` | Nej | `FedoraDev` | Namnet på distrot som ska uppgraderas |
| `-InstallLocation` | Nej | `C:\WSL\FedoraDev` | Var den nya distrots VHDX-fil lagras |
| `-BackupDir` | Nej | `C:\WSL\Backups` | Var `/home`-backupen sparas under uppgraderingen |

### Vad skriptet gör, steg för steg

1. Verifierar `-NewImagePath` mot dess `.sha256`-fil.
2. Kontrollerar att distrot som ska uppgraderas faktiskt finns sedan
   tidigare.
3. Kör `tar czf` INUTI den körande, gamla distrot och skriver resultatet
   direkt till en fil på Windows-sidan under `-BackupDir` - hela `/home`
   säkerhetskopieras, inte bara en användare.
4. Validerar att backupfilen faktiskt går att läsa och lista med
   `tar -tzf` **innan något rörs**. Om valideringen misslyckas avbryts
   uppgraderingen här, och den gamla distrot är fortfarande orörd.
5. Avregistrerar den gamla distrot (`wsl --unregister`) och importerar
   den nya imagen på samma plats och med samma namn.
6. Återställer `/home` från backupen till den nya distrot.
7. Kör `fix-home-ownership.sh` inuti den nya distrot, som rättar
   ägarskapet på varje mapp under `/home` mot den nya imagens
   `/etc/passwd` - robust även om användar-ID:n skulle skilja sig mellan
   gamla och nya imagen.
8. Verifierar `systemd` i den nya distrot.

### Förväntat resultat

```
== Klart. 'FedoraDev' uppgraderad, /home aterstallt. Backup sparad: C:\WSL\Backups\FedoraDev-home-<tidsstampel>.tar.gz ==
```

Backupfilen på Windows-sidan raderas INTE automatiskt - den blir kvar som
säkerhetskopia tills ni själva städar bort den, t.ex. efter att ha
verifierat att utvecklaren är nöjd med den uppgraderade miljön.

### Om något går fel

Skriptet avregistrerar aldrig den gamla distrot förrän backupen är
verifierad läsbar. Om ett fel inträffar EFTER avregistrering (t.ex. att
importen av den nya imagen misslyckas) pekar felmeddelandet ut var
backupfilen ligger, så att ni kan återställa manuellt.

---

## Löpande patchning

Imagen byggs om (Steg 1) vid Fedora major-version-byten, t.ex. 44 → 45 -
inte för varje säkerhetspatch. Löpande säkerhetsuppdateringar mellan
dessa tillfällen sker automatiskt INUTI varje redan utrullad distro via
`dnf5-automatic.timer`, som är aktiverat som standard i imagen.
Utvecklaren eller paketeringsteamet behöver inte göra något för detta.

## Kända problem som redan är åtgärdade i imagen

Dessa två saker är redan fixade i `Containerfile.fedora-golden` - de
listas här för spårbarhet, inte som något ni behöver göra något åt:

- **Fel timer-namn för `dnf-automatic` på Fedora 44+**: Fedora 44 och
  senare använder `dnf5`, så det korrekta systemd-enhetsnamnet är
  `dnf5-automatic.timer`, inte det äldre `dnf-automatic-install.timer`.
- **`newuidmap`/`newgidmap` saknar setuid-bit efter bygget**: när dessa
  binärer installeras under ett rootless `podman build`-anrop misslyckas
  RPM-paketets interna skript med att sätta setuid-biten (krävs för att
  rootless `podman` ska kunna köra containrar inuti Fedora-miljön).
  Åtgärdat genom att imagen kör
  `chmod u+s /usr/bin/newuidmap /usr/bin/newgidmap` vid varje boot via
  `[boot] command` i `/etc/wsl.conf`, oavsett grundorsak till att biten
  försvann.

## Licens

MIT, se [LICENSE](LICENSE).
