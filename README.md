# wsl2-fedora

Reproducerbara Linux-utvecklingsmiljöer för Windows 11-datorer, levererade
via WSL2 - helt utan Microsoft Store. En "gyllene image" byggs en gång
centralt och rullas sedan ut tyst till valfritt antal utvecklardatorer.

**Två imagevarianter finns att välja mellan:**

| | Fedora | Amazon Linux |
|---|---|---|
| Containerfile | [Containerfile.fedora-golden](Containerfile.fedora-golden) | [Containerfile.amazonlinux-golden](Containerfile.amazonlinux-golden) |
| Byggskript | [build-fedora-golden-image.sh](build-fedora-golden-image.sh) | [build-amazonlinux-golden-image.sh](build-amazonlinux-golden-image.sh) |
| Baseimage | `registry.fedoraproject.org/fedora` | `public.ecr.aws/amazonlinux/amazonlinux` |
| Paketmanager | `dnf5` | `dnf4` |
| Containermotor | Podman (rootless) | Docker (root-daemon, devanvändaren i `docker`-gruppen) |
| dnf-automatic-enhet | `dnf5-automatic.timer` | `dnf-automatic-install.timer` |
| Lämplig när... | Ni redan är vana vid Fedora/Podman, eller vill ha rootless containrar utan root-daemon | Er stack är AWS-tung och ni redan standardiserat på Docker/Amazon Linux i produktion |

Utöver containermotorn (Podman vs Docker) och några interna
paketnamn/repo-sökvägar är imagerna funktionellt likvärdiga: samma
AWS-/molnverktygskit, samma `systemd`-uppsättning, samma bygg-/deploy-/
uppgraderingsflöde. Se "Kända problem" längre ner för en fullständig lista
över skillnaderna.

Miljön är i båda fallen en enda WSL2-distro med riktig `systemd`
aktiverat. Det du får när du öppnar den ÄR Fedora eller Amazon Linux, rakt
av - inget extra virtualiseringslager, ingen ytterligare container ovanpå.

## Tre roller i det här flödet

1. **Byggmaskinen** - en valfri maskin (behöver inte vara Windows) med ett
   containerverktyg (`podman`) installerat. Bygger den gyllene imagen en
   gång per Fedora- eller Amazon Linux-version.
2. **Paketeringsteamet** - kör installations-/uppgraderingsskripten mot
   varje utvecklares Windows 11-dator.
3. **Utvecklaren** - använder den färdiga miljön dagligen. Se
   [DEVELOPER-GUIDE.md](DEVELOPER-GUIDE.md).

**Podman/Docker behövs INTE på utvecklarens Windows-dator.** Det behövs
bara på byggmaskinen (för att skapa imagen, alltid via `podman` oavsett
vilken image ni bygger) och finns redan förinstallerat inuti den färdiga
miljön (för utvecklarens eget containerarbete - Podman i Fedora-imagen,
Docker i Amazon Linux-imagen).

## Varför bygger vi våra egna images istället för färdiga WSL-images?

Samma resonemang gäller för båda distroerna - det finns alltid två olika
saker som kan menas med "en färdig WSL-image för X":

- **Den officiella container-baseimagen** (`registry.fedoraproject.org/fedora`
  för Fedora, `public.ecr.aws/amazonlinux/amazonlinux` för Amazon Linux) -
  publicerad och patchad av respektive projekt/leverantör själva (Fedora
  Project respektive AWS). Det är den vi faktiskt använder som grund. WSL
  behöver bara en ren userland-rootfs-tarball (ingen kärna, ingen
  bootloader), vilket är exakt vad en OCI-container-baseimage är - så vi
  använder redan den officiella imagen, bara via `podman export` istället
  för ett färdigpaketerat `.tar`.
- **Tredjeparts WSL-remixer** (t.ex. "Fedora Remix for WSL" från
  WhitewaterFoundry) - community-projekt som historiskt distribuerats via
  Microsoft Store, med extra förkonfiguration ovanpå. INTE publicerade av
  Fedora Project eller AWS själva, utan en tredjeparts sammanställning. Vi
  valde bort den vägen av två skäl:
  1. Microsoft Store är uteslutet oavsett (hårt krav på de
     enterprise-styrda datorerna från start).
  2. Det är ett extra förtroendeled i leveranskedjan - en tredjeparts
     redan anpassade build, istället för att vi själva kontrollerar exakt
     vad som hamnar i imagen och kan spåra ursprunget till en enda källa
     (Fedora Project respektive AWS ECR Public).

Genom att bygga från den officiella baseimagen får vi också full kontroll
för att lägga till `systemd=true`, AWS-verktygen, `wget`-fixen för VS
Code Remote-WSL osv. - något som hade varit svårare att lägga ovanpå
någon annans redan opinionerade remix-build.

## Förinstallerade AWS-/molnverktyg

Utöver grundpaketen och containermotorn (Podman i Fedora-imagen, Docker i
Amazon Linux-imagen) innehåller BÅDA imagerna samma kompletta
AWS-verktygskit, redan installerat och verifierat fungerande (senast
verifierat 2026-09-18):

| Verktyg | Vad det används till |
|---|---|
| `terraform` | Infrastructure-as-code (HashiCorp-repot, finns inte i Fedoras egna repon) |
| `aws` (AWS CLI v2) | Grundläggande AWS-hantering från kommandoraden |
| `git` + `gh` | Versionshantering + GitHub CLI |
| `kubectl` + `eksctl` + `helm` | Kubernetes/EKS-hantering och Helm-charts |
| `sam` (AWS SAM CLI) | Serverless/Lambda-utveckling |
| `cdk` (AWS CDK) | Infrastructure-as-code i vanlig kod (TypeScript/Python m.fl.) |
| `tflint` + `tfsec` + `checkov` | Linting och säkerhetsskanning av Terraform-kod |
| `pre-commit` | Git-hooks för att köra ovanstående automatiskt innan varje commit |
| `aws-vault` | Krypterad lokal lagring av AWS-nycklar/temporära sessioner, istället för klartext i `~/.aws/credentials` |

De flesta av dessa hämtas från respektive leverantörs "senaste
version"-kanal vid byggtillfället (GitHub releases/npm/pip), inte ett
pinnat versionsnummer i `Containerfile.fedora-golden`. Exakt version
speglar alltså när imagen senast byggdes, inte ett löpande
uppdateringsflöde - se "Löpande patchning" nedan. Undantaget är
`kubectl`, som hämtas från en specifik minor-version-kanal
(`v1.31` i skrivande stund) - byt kanal i Containerfilen om ni kör en
annan EKS-version.

**Om VS Code:** medvetet INTE inbakat i imagen. VS Code är designat att
köras på Windows-sidan med tillägget "WSL" installerat - `code`-binären
upptäcker själv om den körs inuti WSL och vägrar/varnar då ("please
install Visual Studio Code in Windows... You can then use the `code`
command in a WSL terminal"). Att baka in den Linux-native `code`-RPM:en
inuti imagen går alltså rakt emot Microsofts egen rekommendation och
skulle bara skapa förvirring. Se
[DEVELOPER-GUIDE.md](DEVELOPER-GUIDE.md) för hur utvecklaren sätter upp
VS Code korrekt mot miljön.

## Filer i det här repot

| Fil | Beskrivning |
|---|---|
| [Containerfile.fedora-golden](Containerfile.fedora-golden) | Definierar innehållet i Fedora-imagen |
| [build-fedora-golden-image.sh](build-fedora-golden-image.sh) | Bygger Fedora-imagen och paketerar den till en WSL2-importbar fil |
| [Containerfile.amazonlinux-golden](Containerfile.amazonlinux-golden) | Definierar innehållet i Amazon Linux-imagen |
| [build-amazonlinux-golden-image.sh](build-amazonlinux-golden-image.sh) | Bygger Amazon Linux-imagen och paketerar den till en WSL2-importbar fil |
| [deploy-fedora-wsl.ps1](deploy-fedora-wsl.ps1) | Installerar WSL2 och miljön på en ny dator - fungerar för BÅDA imagevarianterna (distro-agnostiskt, styrs av `-ImagePath`) |
| [upgrade-fedora-wsl.ps1](upgrade-fedora-wsl.ps1) | Uppgraderar en befintlig installation till en nyare imageversion utan att förlora data - fungerar för BÅDA imagevarianterna |
| [fix-home-ownership.sh](fix-home-ownership.sh) | Hjälpskript som `upgrade-fedora-wsl.ps1` kör internt |
| [DEVELOPER-GUIDE.md](DEVELOPER-GUIDE.md) | Instruktioner för utvecklaren som ska ANVÄNDA miljön dagligen |
| [LICENSE](LICENSE) | MIT-licens |

`deploy-fedora-wsl.ps1`/`upgrade-fedora-wsl.ps1` är trots namnet
distro-agnostiska - de tar bara emot en `.tar`-fil och ett distronamn, och
bryr sig inte om vad som faktiskt ligger i tarballen. Namnen är kvar av
historiska skäl (skrevs innan Amazon Linux-varianten fanns).

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

Fedora:
```bash
./build-fedora-golden-image.sh 44 devuser ./dist
```

Amazon Linux:
```bash
./build-amazonlinux-golden-image.sh 2023 devuser ./dist
```

Parametrarna, i tur och ordning (alla är valfria - utan argument används
värdena nedan som default):

| Parameter | Fedora-exempel | Amazon Linux-exempel | Betyder |
|---|---|---|---|
| 1 | `44` | `2023` | Vilken major-version som ska byggas |
| 2 | `devuser` | `devuser` | Användarnamnet som skapas inuti miljön |
| 3 | `./dist` | `./dist` | Var de färdiga filerna ska hamna |

### Vad skriptet gör

1. Bygger imagen från motsvarande Containerfile med `podman build`.
2. Skapar en tillfällig container från den byggda imagen och exporterar
   dess filsystem till en tarball med `podman export`.
3. Genererar en sha256-checksumma för tarballen.
4. Gör en sanity-check att `/etc/wsl.conf`, `/etc/passwd` och `systemd`
   faktiskt finns med i den färdiga tarballen - avslutar med felkod om
   något saknas.

### Förväntat resultat

Bygget tar normalt 5-15 minuter (mest tid går åt att ladda ner paket).
Efteråt finns två filer i `./dist/`, namngivna efter vilken image ni
byggde:

```
dist/fedora-golden-44-2026.09.18.tar             <- Fedora-imagen, ca 1 GB
dist/fedora-golden-44-2026.09.18.tar.sha256
# eller:
dist/amazonlinux-golden-2023-2026.09.18.tar      <- Amazon Linux-imagen
dist/amazonlinux-golden-2023-2026.09.18.tar.sha256
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
- **Rekommenderas:** kör `wsl --update` en gång på datorn (fungerar utan
  Microsoft Store, uppdaterar bara WSL-plattformen). Löser en känd
  `degraded`-systemd-varning i Fedora-imagen, se "Kända problem" nedan.

### Kör installationen

Öppna PowerShell **som Administratör** och kör:

Fedora:
```powershell
.\deploy-fedora-wsl.ps1 `
  -MsiPath "C:\Installers\Wsl.msi" `
  -ImagePath "\\fileshare\wsl\fedora-golden-44-2026.09.18.tar"
```

Amazon Linux (ange `-DistroName`/`-InstallLocation` explicit så namnet
speglar vad utvecklaren faktiskt får):
```powershell
.\deploy-fedora-wsl.ps1 `
  -MsiPath "C:\Installers\Wsl.msi" `
  -ImagePath "\\fileshare\wsl\amazonlinux-golden-2023-2026.09.18.tar" `
  -DistroName "AmazonLinuxDev" `
  -InstallLocation "C:\WSL\AmazonLinuxDev"
```

Byt ut sökvägarna mot var din WSL-installerare respektive image faktiskt
ligger.

Alla parametrar:

| Parameter | Krävs | Default | Betyder |
|---|---|---|---|
| `-MsiPath` | Endast om WSL inte redan är installerat | - | Sökväg till den fristående WSL-installeraren |
| `-ImagePath` | Ja | - | Sökväg till `fedora-golden-*.tar` eller `amazonlinux-golden-*.tar` |
| `-ChecksumPath` | Nej | `<ImagePath>.sha256` | Sökväg till checksumfilen |
| `-DistroName` | Nej | `FedoraDev` | Namnet WSL-distrot får - sätt t.ex. till `AmazonLinuxDev` för Amazon Linux-imagen |
| `-InstallLocation` | Nej | `C:\WSL\FedoraDev` | Var distrots VHDX-fil lagras |
| `-Force` | Nej | Av | Tar bort och återskapar distrot om den redan finns - **all data i distrot förloras, se varning nedan** |
| `-SkipSetDefault` | Nej | Av | Sätt INTE distrot som WSL:s default - utan flaggan blir `$DistroName` automatiskt det `wsl` (utan `-d`) öppnar |

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
7. Sätter distrot som WSL:s default (`wsl --set-default`), om inte
   `-SkipSetDefault` angetts - så `wsl` utan `-d` öppnar rätt miljö direkt
   istället för en eventuell förinstallerad Ubuntu från en tidigare
   `wsl --install`.
8. Skriver en logg till `C:\ProgramData\FedoraWSLDeploy\deploy-<tidsstämpel>.log`.

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

## Steg 3: Uppgradera en befintlig installation (vid major-version-byte)

Körs av paketeringsteamet när en ny gyllene image (t.ex. Fedora 45 eller
en nyare Amazon Linux-version) har byggts enligt Steg 1, och datorn redan
har en fungerande installation från Steg 2 vars data INTE ska förloras.
Fungerar för båda imagevarianterna (samma skript, distro-agnostiskt).

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

Imagen byggs om (Steg 1) vid major-version-byten, t.ex. Fedora 44 → 45 -
inte för varje säkerhetspatch. Löpande säkerhetsuppdateringar mellan
dessa tillfällen sker automatiskt INUTI varje redan utrullad distro via
respektive distros dnf-automatic-timer, aktiverad som standard i imagen:
`dnf5-automatic.timer` i Fedora-imagen, `dnf-automatic-install.timer` i
Amazon Linux-imagen (se "Kända problem" nedan för varför namnen skiljer
sig). Utvecklaren eller paketeringsteamet behöver inte göra något för
detta.

## Kända problem som redan är åtgärdade i imagerna

Listade här för spårbarhet, inte som något ni behöver göra något åt - allt
nedan är redan fixat i respektive Containerfile.

### Fedora (`Containerfile.fedora-golden`)

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
- **`wget` saknas** - krävs av VS Code Remote-WSL för att hämta VS Code
  Server-komponenten vid första `code .`. Utan den: "Failed to download
  the VS Code server. 'wget' not installed." Åtgärdat genom att `wget`
  ligger med i baseline-paketen.

### Amazon Linux (`Containerfile.amazonlinux-golden`)

Amazon Linux 2023s baseimage skiljer sig från Fedoras på flera punkter
som gav byggfel innan de åtgärdades:

- **`curl` krockar med `curl-minimal`**: baseimagen har redan
  `curl-minimal` förinstallerat, och ett explicit `curl`-paket kan inte
  installeras samtidigt (dnf vägrar, paketen tillhandahåller samma
  filer). Lösning: installera inte `curl` explicit - `curl-minimal`
  räcker för alla https-nedladdningar i Containerfilen.
- **`shadow-utils` saknas i baseimagen** (till skillnad från Fedoras, där
  det finns indirekt): utan det saknas `useradd`/`groupadd`/`usermod`,
  vilket blockerar både devanvändar-skapandet och
  docker-gruppmedlemskapet. Måste anges explicit i paketlistan.
- **`systemd` är inte förinstallerat**: måste anges explicit (Fedoras
  baseimage har det indirekt via andra beroenden).
- **`podman` finns inte i Amazon Linux 2023s egna repon**: Amazon Linux
  saknar Podman i sina officiella paketkällor. Imagen använder `docker`
  istället - en annan arkitektur (root-systemd-daemon istället för
  rootless per-användare), se jämförelsetabellen högst upp. Ingen
  setuid/newuidmap-fix behövs här, eftersom det problemet var specifikt
  för rootless Podman - docker-gruppmedlemskap är vanliga
  Unix-filrättigheter som överlever export/import utan vidare.
- **`gh` finns inte i Amazon Linux 2023s egna repon** (till skillnad från
  Fedora, där det gör det): läggs till via GitHubs officiella repo
  (`cli.github.com/packages/rpm/gh-cli.repo`) innan installation.
- **Terraform-repot har en annan sökväg**: HashiCorps repo för Amazon
  Linux ligger på `rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo`,
  inte samma sökväg som för Fedora.
- **`pip`s `--root-user-action=ignore`-flagga stöds inte**: Amazon Linux
  2023s medföljande pip (21.3.1) är för gammal för den flaggan (som
  används i Fedora-imagen för att tysta en ofarlig varning om att köra
  pip som root). Flaggan utelämnas medvetet i Amazon Linux-imagen -
  varningen skrivs ut men blockerar inget.

### Allmän WSL2-begränsning - `wsl --update` löser den för Fedora, inte (ännu) för Amazon Linux

`systemctl is-system-running` kan visa `degraded` istället för `running`,
och `wsl -d <namn>` kan skriva ut "Failed to start the systemd user
session for '<devuser>'. See journalctl for more details." vid start.
Orsak: `user@1000.service` (per-användar-systemd-sessionen) misslyckas
med `Failed to kill control group ...: Input/output error` (exit
219/CGROUP) - en WSL2-plattformsbegränsning kring cgroup-hantering, inte
ett fel i imagen (`systemd-remount-fs.service` kan också visas som
failed samtidigt - `mount: /: can't find LABEL=/` - helt ofarligt, WSL2:s
virtuella rotfilsystem har ingen LABEL att matcha mot).

**Uppdaterad 2026-09-18: `wsl --update` (kör på Windows-sidan, uppdaterar
hela WSL-plattformen - INTE kopplat till Microsoft Store, fungerar även
på dessa Store-fria enterprise-datorer) löste problemet helt för
FedoraDev**, bekräftat stabilt över flera omstarter och en full
`wsl --shutdown`. WSL-versionen gick från 2.7.13.0 till 2.7.14.0 (samma
kernelversion, 6.18.33.2-2 - fixen satt alltså i WSL-plattformslagret,
inte kerneln).

**AmazonLinuxDev visar fortfarande problemet efter samma uppdatering.**
Skillnaden verkar vara systemd-versionen: Fedora-imagen kör systemd
259.9, Amazon Linux 2023 kör den äldre 252.23 - och AL2023 pinnar den
versionen för hela OS-livscykeln (`dnf list --showduplicates systemd`
visar bara patch-releaser av 252.23, ingen väg till en nyare
major-version via dnf). Detta är alltså sannolikt en samverkan mellan
WSL:s cgroup-delegering och den äldre systemd-versionen, inte något vi
kan fixa i `Containerfile.amazonlinux-golden`.

**Rekommendation:** kör `wsl --update` som en del av grundinstallationen
på varje dator (t.ex. innan `deploy-fedora-wsl.ps1` körs) - det är en
engångsåtgärd på Windows-sidan, inte något som behöver bakas in i
imagerna. Löser problemet helt för Fedora-imagen. För Amazon Linux-imagen
kvarstår det tills antingen WSL eller Amazon Linux patchar sin sida -
**ingetdera påverkar de systemtjänster vi faktiskt beror på**
(`docker.service`, `podman`, `dnf5-automatic.timer`/
`dnf-automatic-install.timer` kör alla som systemtjänster, inte via
per-användar-sessionen, och är verifierat fungerande trots `degraded`).

## Licens

MIT, se [LICENSE](LICENSE).
