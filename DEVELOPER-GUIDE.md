# Fedora på din Windows 11-dator - guide för dig som utvecklare

Din dator har fått en riktig Fedora-miljö förinstallerad via WSL2 (kallad
`FedoraDev` om inte IT namngett den annorlunda). Det här är inte en
virtuell maskin eller en efterhandskonstruktion - det är samma Fedora du
kör som `dnf`, `systemd` och paket från, precis som på en fysisk
Fedora-arbetsstation.

## Komma igång

Öppna en vanlig terminal (Windows Terminal rekommenderas) och kör:

```powershell
wsl -d FedoraDev
```

Du landar direkt i ditt hemkatalog som din vanliga användare, med `sudo`
tillgängligt utan lösenord för lokal utveckling.

**Tips:** lägg till en egen profil i Windows Terminal
(`Inställningar → Lägg till ny profil`) med kommandot `wsl.exe -d
FedoraDev` så får du en flik/genväg som öppnar Fedora direkt.

## Var ska jag spara mina filer?

**Spara källkod och projekt i din Linux-hemkatalog** (`/home/<ditt
användarnamn>/...`), inte under `/mnt/c/...`. `/mnt/c` är hela din
Windows-disk sedd från Linux-sidan - den funkar, men är betydligt
långsammare för saker som `git`, kompilering och paketbyggen eftersom
filsystemet går via en Windows-brygga. Din hemkatalog ligger på ett
riktigt Linux-filsystem inuti WSL2 och är lika snabb som på en fysisk
Fedora-maskin.

Om du behöver komma åt en fil från Windows-sidan (t.ex. dra in den i ett
Windows-program) hittar du din Linux-hemkatalog på:

```
\\wsl.localhost\FedoraDev\home\<ditt användarnamn>\
```

## Installera paket

Vanlig Fedora, vanlig `dnf`:

```bash
sudo dnf install <paketnamn>
```

## Grafiska program (GUI)

Fungerar automatiskt - ingen konfiguration behövs. Installera ett
grafiskt program och kör det, så dyker fönstret upp på ditt
Windows-skrivbord precis som vilket Windows-program som helst:

```bash
sudo dnf install gimp
gimp
```

## Containrar (Podman)

`podman` är redan installerat och fungerar rootless utan extra
konfiguration - inget `podman machine`, ingen Distrobox behövs, du kör
containrar direkt:

```bash
podman run --rm -it fedora:latest bash
```

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
`Containerfile.fedora-golden` använder för det verktyget - se repots
README.

## Säkerhetsuppdateringar

Sker automatiskt i bakgrunden via `dnf5-automatic` - du behöver inte
manuellt köra `dnf update` för säkerhetspatchar (även om det aldrig är fel
att göra det själv med jämna mellanrum för att hålla paket à jour).

## VS Code

Installera tillägget **"WSL"** i VS Code på Windows-sidan, öppna sedan en
terminal i Fedora-miljön och kör:

```bash
code .
```

från din projektmapp - VS Code öppnas då anslutet direkt mot Fedora-miljön,
med terminal, extensions och debugger körandes i Linux.

## Om något går sönder

Din `/home`-katalog är det enda som är unikt för dig - själva Fedora-miljön
kan IT-avdelningen bygga om och skicka ut på nytt (t.ex. vid en
Fedora-versionsuppgradering) utan att du förlorar ditt arbete, eftersom
`/home` alltid flyttas med. Om något känns trasigt i systemet i övrigt,
kontakta IT/paketeringsteamet - de kan återställa miljön från en känd god
image.

## Vanliga frågor

**Startar Fedora automatiskt när jag startar datorn?**
Nej, WSL-distron startar först när du öppnar den (`wsl -d FedoraDev`) och
stängs av automatiskt efter en stund av inaktivitet. Det är helt normalt.

**Kan jag ha flera terminalfönster öppna mot samma Fedora samtidigt?**
Ja, alla delar samma körande instans och filsystem.

**Var är min gamla `/home`-data efter en uppgradering?**
Den ska följa med automatiskt vid en uppgradering utförd av IT. Hör av dig
om något saknas efter en uppgradering - då finns en säkerhetskopia kvar
hos paketeringsteamet.
