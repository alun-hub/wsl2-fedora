<#
.SYNOPSIS
  Uppgraderar en befintlig WSL-distro (Fedora- eller Amazon Linux-baserad,
  distro-agnostiskt) till en ny gyllene image UTAN att forlora /home.
  Anvands vid major-version-byten (t.ex. Fedora 41 -> 44).

.DESCRIPTION
  Lopande sakerhetspatchar mellan majorversioner tacks av dnf-automatic
  INUTI den korande distrot (aktiverat i respektive Containerfile) - det
  har scriptet ar bara for de mer sallsynta major-version-bytena, dar
  imagen byggs om fran grunden.

  Flode:
    1. Verifierar den nya imagens checksumma.
    2. Backar upp hela /home fran den korande distrot till en tar.gz DIREKT
       pa Windows-sidan (via /mnt/c fran distrot - ingen pipe/UNC-hack).
    3. Validerar att backupen ar en laslig, icke-tom arkivfil innan nagot
       som helst forstors. Avbryts uppgraderingen har ror scriptet INTE
       den befintliga distrot.
    4. Avregistrerar den gamla distrot och importerar den nya gyllene
       imagen pa samma plats/namn.
    5. Aterstaller /home fran backupen och fixar agarskap mot den NYA
       imagens /etc/passwd (se fix-home-ownership.sh).
    6. Verifierar systemd-status.

  Backup-tarballen i -BackupDir raderas INTE automatiskt - den ar kvar som
  sakerhetskopia tills ni stadar den manuellt (t.ex. efter att ha verifierat
  att utvecklaren ar nojd med den uppgraderade miljon).

.PARAMETER DistroName
  Namn pa den befintliga WSL-distrot som ska uppgraderas. Default: FedoraDev

.PARAMETER NewImagePath
  Sokvag till den nya fedora-golden-*.tar (hogre Fedora-version).

.PARAMETER ChecksumPath
  Sokvag till motsvarande .sha256-fil. Om utelamnad forsoks
  "<NewImagePath>.sha256" automatiskt.

.PARAMETER InstallLocation
  Var den nya distrots VHDX ska ligga. Default: C:\WSL\<DistroName>

.PARAMETER BackupDir
  Var /home-backupen sparas pa Windows-sidan. Default: C:\WSL\Backups

.EXAMPLE
  .\upgrade-fedora-wsl.ps1 -NewImagePath \\fileshare\wsl\fedora-golden-44-2026.09.18.tar
#>

[CmdletBinding()]
param(
    [string]$DistroName = "FedoraDev",
    [Parameter(Mandatory = $true)]
    [string]$NewImagePath,
    [string]$ChecksumPath,
    [string]$InstallLocation = "C:\WSL\FedoraDev",
    [string]$BackupDir = "C:\WSL\Backups"
)

$ErrorActionPreference = "Stop"
$LogFile = Join-Path $env:ProgramData "FedoraWSLDeploy\upgrade-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
New-Item -ItemType Directory -Force -Path (Split-Path $LogFile) | Out-Null
New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Windows-sokvag -> /mnt/<drive>/... sokvag som ar laslig/skrivbar fran
# INUTI en WSL-distro via automatisk DrvFs-montering.
function Convert-ToWslPath {
    param([string]$WindowsPath)
    $full = (Resolve-Path -LiteralPath (Split-Path $WindowsPath)).Path
    $leaf = Split-Path $WindowsPath -Leaf
    $drive = $full.Substring(0, 1).ToLower()
    $rest = $full.Substring(2).Replace("\", "/")
    return "/mnt/$drive$rest/$leaf"
}

try {
    if (-not (Test-IsAdmin)) {
        Write-Log "Scriptet maste koras som Administrator." "ERROR"
        exit 1
    }

    Write-Log "== Steg 1: Verifiera ny image =="
    if (-not (Test-Path $NewImagePath)) {
        Write-Log "Hittar inte imagen: $NewImagePath" "ERROR"
        exit 1
    }
    if (-not $ChecksumPath) { $ChecksumPath = "$NewImagePath.sha256" }
    if (Test-Path $ChecksumPath) {
        $expected = (Get-Content $ChecksumPath -Raw).Split(" ")[0].Trim()
        $actual = (Get-FileHash -Path $NewImagePath -Algorithm SHA256).Hash.ToLower()
        if ($expected.ToLower() -ne $actual) {
            Write-Log "Checksumma matchar INTE for $NewImagePath. Avbryter." "ERROR"
            exit 1
        }
        Write-Log "Checksumma OK."
    } else {
        Write-Log "Ingen checksumfil hittad ($ChecksumPath) - hoppar over verifiering." "WARN"
    }

    $existing = (wsl --list --quiet 2>$null) -replace "`0", "" | Where-Object { $_.Trim() -eq $DistroName }
    if (-not $existing) {
        Write-Log "Distro '$DistroName' finns inte. Anvand deploy-fedora-wsl.ps1 for forsta installation istallet." "ERROR"
        exit 1
    }

    Write-Log "== Steg 2: Backa upp /home fran den korande distrot =="
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupTarWin = Join-Path $BackupDir "$DistroName-home-$stamp.tar.gz"
    $backupTarWsl = Convert-ToWslPath -WindowsPath $backupTarWin

    # Skrivs direkt till Windows-sidan fran distrot - ingen mellanlagring
    # i distrots eget /tmp, inget separat kopieringssteg.
    wsl -d $DistroName -- sudo tar czf "$backupTarWsl" -C /home .
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Backup av /home misslyckades (exitkod $LASTEXITCODE). Avbryter - distrot ar OROD." "ERROR"
        exit 1
    }

    Write-Log "== Steg 3: Validera backupen innan nagot forstors =="
    if (-not (Test-Path $backupTarWin) -or (Get-Item $backupTarWin).Length -lt 1024) {
        Write-Log "Backupfilen saknas eller ar orimligt liten. Avbryter - distrot ar OROD." "ERROR"
        exit 1
    }
    $listing = wsl -d $DistroName -- tar -tzf "$backupTarWsl" 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $listing) {
        Write-Log "Backupen gick inte att lasa/lista. Avbryter - distrot ar OROD." "ERROR"
        exit 1
    }
    Write-Log "Backup OK: $backupTarWin ($((Get-Item $backupTarWin).Length) bytes, $((($listing) | Measure-Object).Count) poster)"

    Write-Log "== Steg 4: Avregistrera gammal distro och importera ny image =="
    wsl --unregister $DistroName | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Kunde inte avregistrera '$DistroName'. Backupen ligger kvar pa $backupTarWin." "ERROR"
        exit 1
    }

    New-Item -ItemType Directory -Force -Path $InstallLocation | Out-Null
    wsl --import $DistroName $InstallLocation $NewImagePath --version 2
    if ($LASTEXITCODE -ne 0) {
        Write-Log "wsl --import misslyckades. Distrot ar BORTA - aterimportera manuellt fran gammal eller ny image. Backup finns pa $backupTarWin." "ERROR"
        exit 1
    }
    wsl -d $DistroName -- true | Out-Null

    Write-Log "== Steg 5: Aterstall /home fran backupen =="
    wsl -d $DistroName -- sudo tar xzf "$backupTarWsl" -C /home
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Aterstallning av /home misslyckades. Backup finns kvar pa $backupTarWin - aterstall manuellt." "ERROR"
        exit 1
    }

    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $fixScriptWin = Join-Path $scriptDir "fix-home-ownership.sh"
    if (Test-Path $fixScriptWin) {
        $fixScriptWsl = Convert-ToWslPath -WindowsPath $fixScriptWin
        wsl -d $DistroName -- sudo bash "$fixScriptWsl"
    } else {
        Write-Log "fix-home-ownership.sh hittades inte bredvid scriptet - agarskap under /home kan behova rattas manuellt (chown)." "WARN"
    }

    Write-Log "== Steg 6: Verifiera systemd =="
    $status = (wsl -d $DistroName -- systemctl is-system-running 2>$null).Trim()
    Write-Log "systemctl is-system-running -> '$status'"
    if ($status -notin @("running", "degraded")) {
        Write-Log "Systemd rapporterar ovantat tillstand ('$status'). Kontrollera manuellt." "WARN"
    }

    Write-Log "== Klart. '$DistroName' uppgraderad, /home aterstallt. Backup sparad: $backupTarWin =="
    exit 0
}
catch {
    Write-Log "Ovantat fel: $($_.Exception.Message)" "ERROR"
    Write-Log $_.ScriptStackTrace "ERROR"
    exit 1
}
