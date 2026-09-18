# Fedora/Amazon Linux på din Windows 11-dator - guide för dig som utvecklare

Din dator har fått en riktig Linux-miljö förinstallerad via WSL2 - antingen
Fedora (distronamnet är då `FedoraDev` om inte IT namngett den
annorlunda) eller Amazon Linux (`AmazonLinuxDev`). Kör `wsl -l -v` i
PowerShell om du är osäker på vilken du har. Det här är inte en virtuell
maskin eller en efterhandskonstruktion - det är samma distro du kör som
`dnf`, `systemd` och paket från, precis som på en fysisk arbetsstation.
Den här guiden gäller för båda - de skiljer sig bara åt kring
containerverktyget (Podman vs Docker), se avsnittet "Containrar" nedan.

## Komma igång

Öppna en vanlig terminal (Windows Terminal rekommenderas) och kör (byt ut
`FedoraDev` mot `AmazonLinuxDev` om det är den du fått):

```powershell
wsl -d FedoraDev
```

Du landar direkt i ditt hemkatalog som din vanliga användare, med `sudo`
tillgängligt utan lösenord för lokal utveckling.

**Tips:** lägg till en egen profil i Windows Terminal
(`Inställningar → Lägg till ny profil`) med kommandot `wsl.exe -d
FedoraDev` (eller `AmazonLinuxDev`) så får du en flik/genväg som öppnar
miljön direkt.

## Var ska jag spara mina filer?

**Spara källkod och projekt i din Linux-hemkatalog** (`/home/<ditt
användarnamn>/...`), inte under `/mnt/c/...`. `/mnt/c` är hela din
Windows-disk sedd från Linux-sidan - den funkar, men är betydligt
långsammare för saker som `git`, kompilering och paketbyggen eftersom
filsystemet går via en Windows-brygga. Din hemkatalog ligger på ett
riktigt Linux-filsystem inuti WSL2 och är lika snabb som på en fysisk
Linux-maskin.

Om du behöver komma åt en fil från Windows-sidan (t.ex. dra in den i ett
Windows-program) hittar du din Linux-hemkatalog på:

```
\\wsl.localhost\FedoraDev\home\<ditt användarnamn>\
```
(byt `FedoraDev` mot `AmazonLinuxDev` om det är den du har)

## Installera paket

Vanlig `dnf` (samma kommando i båda imagerna):

```bash
sudo dnf install <paketnamn>
```

## Grafiska program (GUI)

Fungerar automatiskt - ingen konfiguration behövs. Installera ett
grafiskt program och kör det, så dyker fönstret upp på ditt
Windows-skrivbord precis som vilket Windows-program som helst:

```bash
sudo dnf install xterm
xterm
```

(Paketutbudet skiljer sig något mellan Fedora och Amazon Linux - Amazon
Linux 2023 är en serverfokuserad distro och saknar t.ex. `gimp` i sina
repon. `xterm` ovan finns i båda som ett minimalt exempel; större
GUI-program kan behöva sökas upp separat beroende på vilken image du
har.)

## Containrar (Podman eller Docker)

**Fedora-imagen:** `podman` är redan installerat och fungerar rootless
utan extra konfiguration - inget `podman machine`, ingen Distrobox
behövs, du kör containrar direkt:

```bash
podman run --rm -it fedora:latest bash
```

**Amazon Linux-imagen:** `docker` är redan installerat, tjänsten är
aktiverad, och din användare är redan medlem i `docker`-gruppen - du kör
containrar direkt utan `sudo`:

```bash
docker run --rm -it amazonlinux:2023 bash
```

Om du får `permission denied` mot docker-sockeln direkt efter en
ombyggnad/uppgradering: gruppmedlemskapet läses in vid inloggning, så
stäng och öppna ett nytt `wsl -d AmazonLinuxDev`-fönster (eller kör
`newgrp docker` i det befintliga).

## AWS-verktyg

Redan förinstallerat, inget extra att göra: `terraform`, `aws` (AWS CLI
v2), `gh` (GitHub CLI), `kubectl`, `eksctl`, `helm`, `sam` (AWS SAM CLI),
`cdk` (AWS CDK), `tflint`, `tfsec`, `checkov`, `pre-commit` och
`aws-vault`.

**Hantera dina AWS-inloggningsuppgifter med `aws-vault`** istället för att
lägga AWS-nycklar i klartext i `~/.aws/credentials`:

```bash
aws-vault add mitt-aws-konto
aws-vault exec mitt-aws-konto -- aws s3 ls
```

Behöver du en nyare version av ett enskilt verktyg mellan
imageuppgraderingar kan du köra om samma installationskommando som
`Containerfile.fedora-golden`/`Containerfile.amazonlinux-golden` använder
för det verktyget - se repots README.

## Säkerhetsuppdateringar

Sker automatiskt i bakgrunden via distrots dnf-automatic-tjänst - du
behöver inte manuellt köra `dnf update` för säkerhetspatchar (även om det
aldrig är fel att göra det själv med jämna mellanrum för att hålla paket
à jour).

## VS Code

Installera tillägget **"WSL"** i VS Code på Windows-sidan, öppna sedan en
terminal i miljön och kör:

```bash
code .
```

från din projektmapp - VS Code öppnas då anslutet direkt mot miljön, med
terminal, extensions och debugger körandes i Linux.

## Om något går sönder

Din `/home`-katalog är det enda som är unikt för dig - själva miljön kan
IT-avdelningen bygga om och skicka ut på nytt (t.ex. vid en
versionsuppgradering) utan att du förlorar ditt arbete, eftersom `/home`
alltid flyttas med. Om något känns trasigt i systemet i övrigt, kontakta
IT/paketeringsteamet - de kan återställa miljön från en känd god image.

## Vanliga frågor

**Startar miljön automatiskt när jag startar datorn?**
Nej, WSL-distron startar först när du öppnar den (`wsl -d FedoraDev`
eller `wsl -d AmazonLinuxDev`) och stängs av automatiskt efter en stund
av inaktivitet. Det är helt normalt.

**Kan jag ha flera terminalfönster öppna mot samma miljö samtidigt?**
Ja, alla delar samma körande instans och filsystem.

**Var är min gamla `/home`-data efter en uppgradering?**
Den ska följa med automatiskt vid en uppgradering utförd av IT. Hör av dig
om något saknas efter en uppgradering - då finns en säkerhetskopia kvar
hos paketeringsteamet.
