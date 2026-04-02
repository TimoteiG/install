# =============================================================================
#  silent-install.ps1  -  GitHub edition
# =============================================================================

# -------------------------------------------------------
# CONFIGURATIE - Editeaza aceasta sectiune
# -------------------------------------------------------
$installers = @(
    @{
        Name = "WinRAR"
        Url  = "https://github.com/TimoteiG/install/raw/main/winrar-x64-711.exe"
    },
    @{
        Name = "Everything"
        Url  = "https://github.com/TimoteiG/install/raw/main/Everything-1.4.1.1032.x86-Setup.exe"
    },
    @{
        Name = "Acrobat Reader"
        Url  = "https://github.com/TimoteiG/install/raw/main/Reader_ro_install.exe"
    }
    # Adauga cate intrari vrei, dupa acelasi format
)

$downloadFolder = "$env:TEMP\SilentInstallers"

# -------------------------------------------------------
# FUNCTII
# -------------------------------------------------------

function Fix-GithubUrl {
    param([string]$Url)
    # Converteste /blob/ in /raw/ daca userul a copiat linkul gresit
    return $Url -replace "github\.com/([^/]+)/([^/]+)/blob/", "github.com/`$1/`$2/raw/"
}

function Get-InstallerType {
    param([string]$FilePath)

    $bytes = [System.IO.File]::ReadAllBytes($FilePath) | Select-Object -First 264

    if ($bytes[0] -eq 0xD0 -and $bytes[1] -eq 0xCF -and $bytes[2] -eq 0x11 -and $bytes[3] -eq 0xE0) {
        return "MSI"
    }

    $content = [System.IO.File]::ReadAllBytes($FilePath) | Select-Object -First 65536
    $text = [System.Text.Encoding]::ASCII.GetString($content) -replace '[^\x20-\x7E]', ''

    if ($text -match "Nullsoft")      { return "NSIS" }
    if ($text -match "Inno Setup")    { return "InnoSetup" }
    if ($text -match "InstallShield") { return "InstallShield" }
    if ($text -match "WiX|Windows Installer XML") { return "WiX" }

    return "Unknown"
}

function Get-SilentArgs {
    param([string]$InstallerType)
    switch ($InstallerType) {
        "MSI"           { return @("/qn", "/norestart") }
        "NSIS"          { return @("/S") }
        "InnoSetup"     { return @("/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART") }
        "InstallShield" { return @("/s", "/v`"/qn`"") }
        "WiX"           { return @("/quiet", "/norestart") }
        default         { return @("/S", "/quiet", "/silent") }
    }
}

# -------------------------------------------------------
# SCRIPT PRINCIPAL
# -------------------------------------------------------

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[ATENTIE] Ruleaza PowerShell ca Administrator!" -ForegroundColor Yellow
}

if (-not (Test-Path $downloadFolder)) {
    New-Item -ItemType Directory -Path $downloadFolder | Out-Null
}

$results = @()
$total   = $installers.Count
$current = 0

foreach ($app in $installers) {
    $current++
    Write-Host "`n[$current/$total] $($app.Name)" -ForegroundColor Cyan
    Write-Host "-----------------------------------------" -ForegroundColor DarkGray

    $safeName = $app.Name -replace '[\\/:*?"<>|]', '_'
    $exePath  = Join-Path $downloadFolder "$safeName.exe"

    # DOWNLOAD
    try {
        $url = Fix-GithubUrl -Url $app.Url
        Write-Host "  [1/3] Download din: $url" -ForegroundColor White

        # Download simplu si direct
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "PowerShell")
        $wc.DownloadFile($url, $exePath)

        $fileSize = (Get-Item $exePath).Length
        if ($fileSize -lt 10000) {
            throw "Fisierul descarcat e prea mic ($fileSize bytes) - verifica URL-ul sau ca fisierul e in repo."
        }

        $sizeMB = [math]::Round($fileSize / 1MB, 1)
        Write-Host "        OK - $sizeMB MB" -ForegroundColor Green
    }
    catch {
        Write-Host "        EROARE download: $_" -ForegroundColor Red
        $results += [PSCustomObject]@{ App = $app.Name; Status = "EROARE DOWNLOAD"; Detalii = $_.Exception.Message }
        continue
    }

    # DETECTIE TIP
    Write-Host "  [2/3] Detectez tipul..." -ForegroundColor White
    $installerType = Get-InstallerType -FilePath $exePath
    $silentArgs    = Get-SilentArgs -InstallerType $installerType
    Write-Host "        Tip: $installerType | Args: $($silentArgs -join ' ')" -ForegroundColor Yellow

    # INSTALARE SILENTA
    Write-Host "  [3/3] Instalez..." -ForegroundColor White
    try {
        if ($installerType -eq "MSI") {
            $proc = Start-Process "msiexec.exe" -ArgumentList (@("/i", "`"$exePath`"") + $silentArgs) -Wait -PassThru
        } else {
            $proc = Start-Process $exePath -ArgumentList $silentArgs -Wait -PassThru
        }

        if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
            $status = if ($proc.ExitCode -eq 3010) { "OK (restart necesar)" } else { "OK" }
            Write-Host "        Instalare reusita! (Exit: $($proc.ExitCode))" -ForegroundColor Green
        } else {
            $status = "EROARE (exit $($proc.ExitCode))"
            Write-Host "        Instalare esuata. Exit: $($proc.ExitCode)" -ForegroundColor Red
        }
    }
    catch {
        $status = "EROARE INSTALARE"
        Write-Host "        EROARE: $_" -ForegroundColor Red
    }

    $results += [PSCustomObject]@{
        App       = $app.Name
        Tip       = $installerType
        Argumente = ($silentArgs -join " ")
        Status    = $status
    }
}

# SUMAR
Write-Host "`n=========================================" -ForegroundColor Cyan
Write-Host "  SUMAR INSTALARI" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
$results | Format-Table -AutoSize

Write-Host "`nGata! Apasa Enter pentru a inchide..." -ForegroundColor Green
Read-Host
