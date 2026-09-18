<#
.SYNOPSIS
  Installerar WSL2 (utan Microsoft Store) och importerar en fardigbyggd
  Fedora-golden-image som en WSL2-distro. Korts av paketeringsteamet via
  Intune/SCCM/valfritt MDM-verktyg pa enterprise-styrda Windows 11-datorer.

.DESCRIPTION
  Idempotent: kan koras om utan att gora om redan klara steg. Anvander
  Windows installer-liknande exitkoder sa att MDM-verktyg kan tolka
  resultatet:
    0    = Lyckades, inget mer behovs
    3010 = Lyckades men kraver omstart (t.ex. forsta gangen DISM-features
           aktiveras) - kor scriptet igen efter omstart for att slutfora
    1    = Fel, se loggfil

.PARAMETER MsiPath
  Sokvag till den fristaende WSL-MSI:n (fran GitHub Releases, staged internt
  - INTE Store). Kravs forsta gangen wsl.exe saknas.

.PARAMETER ImagePath
  Sokvag (lokal eller UNC) till fedora-golden-*.tar fran
  build-fedora-golden-image.sh.

.PARAMETER ChecksumPath
  Sokvag till motsvarande .sha256-fil. Om utelamnad forsoks
  "<ImagePath>.sha256" automatiskt.

.PARAMETER DistroName
  Namn pa WSL-distrot. Default: FedoraDev

.PARAMETER InstallLocation
  Var distrots VHDX ska ligga. Default: C:\WSL\<DistroName>

.PARAMETER Force
  Tar bort och importerar om distrot aven om det redan finns.

.PARAMETER SkipSetDefault
  Satt INTE distrot som WSL:s default. Utan denna flagga blir $DistroName
  automatiskt det bare `wsl` (utan -d) oppnar - anvandbart nar en dator
  bara ska ha en dev-distro. Anvand -SkipSetDefault om datorn ska ha
  flera parallella distros och ni inte vill att den har korningen andrar
  vilken som ar default.

.EXAMPLE
  .\deploy-fedora-wsl.ps1 -MsiPath \\fileshare\wsl\Wsl.msi `
    -ImagePath \\fileshare\wsl\fedora-golden-41-2026.09.18.tar
#>

[CmdletBinding()]
param(
    [string]$MsiPath,
    [Parameter(Mandatory = $true)]
    [string]$ImagePath,
    [string]$ChecksumPath,
    [string]$DistroName = "FedoraDev",
    [string]$InstallLocation = "C:\WSL\FedoraDev",
    [switch]$Force,
    [switch]$SkipSetDefault
)

$ErrorActionPreference = "Stop"
$LogFile = Join-Path $env:ProgramData "FedoraWSLDeploy\deploy-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
New-Item -ItemType Directory -Force -Path (Split-Path $LogFile) | Out-Null

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

try {
    if (-not (Test-IsAdmin)) {
        Write-Log "Scriptet maste koras som Administrator (DISM kraver det)." "ERROR"
        exit 1
    }

    Write-Log "== Steg 1: Windows-funktioner (WSL + VirtualMachinePlatform) =="
    $rebootNeeded = $false
    foreach ($feature in @("Microsoft-Windows-Subsystem-Linux", "VirtualMachinePlatform")) {
        $state = (Get-WindowsOptionalFeature -Online -FeatureName $feature).State
        if ($state -ne "Enabled") {
            Write-Log "Aktiverar $feature ..."
            $result = Enable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart
            if ($result.RestartNeeded) { $rebootNeeded = $true }
        } else {
            Write-Log "$feature redan aktiverad."
        }
    }

    if ($rebootNeeded) {
        Write-Log "Omstart kravs innan WSL2 kan anvandas. Kor scriptet igen efter omstart." "WARN"
        exit 3010
    }

    Write-Log "== Steg 2: WSL-motorn (fristaende MSI, inte Store) =="
    $wslInstalled = $false
    try {
        $null = wsl --status 2>$null
        if ($LASTEXITCODE -eq 0) { $wslInstalled = $true }
    } catch { $wslInstalled = $false }

    if (-not $wslInstalled) {
        if (-not $MsiPath -or -not (Test-Path $MsiPath)) {
            Write-Log "wsl.exe saknas och -MsiPath pekar inte pa en giltig fil. Kan inte fortsatta." "ERROR"
            exit 1
        }
        Write-Log "Installerar WSL fran $MsiPath ..."
        $p = Start-Process msiexec.exe -ArgumentList "/i `"$MsiPath`" /quiet /norestart" -Wait -PassThru
        if ($p.ExitCode -notin @(0, 3010)) {
            Write-Log "msiexec misslyckades med kod $($p.ExitCode)." "ERROR"
            exit 1
        }
        if ($p.ExitCode -eq 3010) {
            Write-Log "WSL installerat men kraver omstart. Kor scriptet igen efter omstart." "WARN"
            exit 3010
        }
    } else {
        Write-Log "WSL redan installerat."
    }

    wsl --set-default-version 2 | Out-Null

    Write-Log "== Steg 3: Verifiera image-integritet =="
    if (-not (Test-Path $ImagePath)) {
        Write-Log "Hittar inte imagen: $ImagePath" "ERROR"
        exit 1
    }
    if (-not $ChecksumPath) { $ChecksumPath = "$ImagePath.sha256" }
    if (Test-Path $ChecksumPath) {
        $expected = (Get-Content $ChecksumPath -Raw).Split(" ")[0].Trim()
        $actual = (Get-FileHash -Path $ImagePath -Algorithm SHA256).Hash.ToLower()
        if ($expected.ToLower() -ne $actual) {
            Write-Log "Checksumma matchar INTE for $ImagePath. Forvantad $expected, fick $actual." "ERROR"
            exit 1
        }
        Write-Log "Checksumma OK."
    } else {
        Write-Log "Ingen checksumfil hittades ($ChecksumPath) - hoppar over verifiering." "WARN"
    }

    Write-Log "== Steg 4: Importera Fedora-distro '$DistroName' =="
    $existing = (wsl --list --quiet 2>$null) -replace "`0", "" | Where-Object { $_.Trim() -eq $DistroName }
    if ($existing) {
        if ($Force) {
            Write-Log "Distro finns redan, tar bort (-Force) ..."
            wsl --unregister $DistroName | Out-Null
        } else {
            Write-Log "Distro '$DistroName' finns redan. Anvand -Force for att ersatta. Hoppar over import."
        }
    }

    $existingAfter = (wsl --list --quiet 2>$null) -replace "`0", "" | Where-Object { $_.Trim() -eq $DistroName }
    if (-not $existingAfter) {
        New-Item -ItemType Directory -Force -Path $InstallLocation | Out-Null
        Write-Log "Kor: wsl --import $DistroName $InstallLocation $ImagePath --version 2"
        wsl --import $DistroName $InstallLocation $ImagePath --version 2
        if ($LASTEXITCODE -ne 0) {
            Write-Log "wsl --import misslyckades med kod $LASTEXITCODE." "ERROR"
            exit 1
        }
    }

    Write-Log "== Steg 5: Forsta boot + verifiera systemd =="
    wsl -d $DistroName -- true | Out-Null
    Start-Sleep -Seconds 2
    $status = (wsl -d $DistroName -- systemctl is-system-running 2>$null).Trim()
    Write-Log "systemctl is-system-running -> '$status'"
    if ($status -notin @("running", "degraded")) {
        Write-Log "Systemd rapporterar ovantat tillstand ('$status'). Kontrollera imagen manuellt." "WARN"
    } else {
        Write-Log "Systemd OK ('$status')."
    }

    if (-not $SkipSetDefault) {
        Write-Log "== Steg 6: Satt '$DistroName' som WSL-default =="
        wsl --set-default $DistroName | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Log "Kunde inte satta '$DistroName' som default (exitkod $LASTEXITCODE) - fortsatter anda, distrot fungerar fortfarande via -d." "WARN"
        } else {
            Write-Log "'$DistroName' ar nu WSL-default - 'wsl' utan -d oppnar den direkt."
        }
    }

    Write-Log "== Klart: '$DistroName' ar redo. Utvecklaren startar med: wsl -d $DistroName =="
    exit 0
}
catch {
    Write-Log "Ovantat fel: $($_.Exception.Message)" "ERROR"
    Write-Log $_.ScriptStackTrace "ERROR"
    exit 1
}
