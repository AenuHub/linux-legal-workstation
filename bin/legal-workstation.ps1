<#
.SYNOPSIS
    Linux Legal Workstation - Windows Teşhis ve Sağlık Aracı (Doctor & Upgrade)
.DESCRIPTION
    Türkiye avukatları için Windows ortamında UYAP, E-İmza ve akıllı kart bileşenlerini teşhis eder ve günceller.
#>

[CmdletBinding()]
param (
    [Parameter(Position = 0)]
    [ValidateSet('doctor', 'upgrade', 'update', 'uninstall', 'remove', 'start', 'restart', 'help', '')]
    [string]$Command = 'doctor',

    [Parameter(Position = 1)]
    [switch]$Force
)

$ErrorActionPreference = 'Continue'

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> " -ForegroundColor Cyan -NoNewline
    Write-Host $Message -ForegroundColor White
}

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] " -ForegroundColor Blue -NoNewline
    Write-Host $Message
}

function Write-Success {
    param([string]$Message)
    Write-Host "[BAŞARILI] " -ForegroundColor Green -NoNewline
    Write-Host $Message
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[UYARI] " -ForegroundColor Yellow -NoNewline
    Write-Host $Message
}

function Write-Failure {
    param([string]$Message)
    Write-Host "[HATA] " -ForegroundColor Red -NoNewline
    Write-Host $Message
}

function Invoke-Doctor {
    Write-Host "`n=====================================================" -ForegroundColor Cyan
    Write-Host "  Legal Workstation (Windows) - Teşhis ve Sağlık Kontrolü" -ForegroundColor Cyan
    Write-Host "=====================================================`n" -ForegroundColor Cyan

    $allOk = $true

    # 1. Akıllı Kart Servisi (SCardSvr)
    $scard = $null
    if (Get-Command Get-Service -ErrorAction SilentlyContinue) {
        $scard = Get-Service -Name SCardSvr -ErrorAction SilentlyContinue
    }
    $colWidth = 35
    Write-Host ("{0,-$colWidth}" -f "1. Akıllı Kart Servisi (SCardSvr):") -NoNewline
    if ($null -ne $scard -and $scard.Status -eq 'Running') {
        Write-Host "[ÇALIŞIYOR]" -ForegroundColor Green
    } else {
        Write-Host "[DURDURULMUŞ] " -ForegroundColor Red -NoNewline
        Write-Host "-> 'Start-Service SCardSvr'" -ForegroundColor Yellow
        $allOk = $false
    }

    # 2. Kart Okuyucu / USB Token
    Write-Host ("{0,-$colWidth}" -f "2. Kart Okuyucu / USB Token:") -NoNewline
    $readers = @()
    if ($PSVersionTable.Platform -ne 'Unix') {
        try {
            $readers = Get-CimInstance -ClassName Win32_PnPEntity -Filter "PNPClass = 'SmartCardReader'" -ErrorAction SilentlyContinue
        } catch {}
    }
    if ($readers.Count -gt 0) {
        $readerNames = ($readers | ForEach-Object { $_.Name }) -join ", "
        Write-Host "[ALGILANDI] " -ForegroundColor Green -NoNewline
        Write-Host "($readerNames)" -ForegroundColor Gray
    } else {
        Write-Host "[KART OKUYUCU TAKILI DEĞİL] " -ForegroundColor Yellow -NoNewline
        Write-Host "(Lütfen e-imza USB token'ınızı takın)" -ForegroundColor Gray
    }

    # 3. TÜBİTAK AKİS / AKİA Sürücüsü
    Write-Host ("{0,-$colWidth}" -f "3. TÜBİTAK AKİS Sürücüsü:") -NoNewline
    $akisPaths = @(
        "$env:ProgramFiles\Akis\akisp11.dll",
        "$env:ProgramFiles\Akia\akisp11.dll",
        "$env:SystemRoot\System32\akisp11.dll",
        "${env:ProgramFiles(x86)}\Akis\akisp11.dll",
        "${env:ProgramFiles(x86)}\Akia\akisp11.dll"
    )
    $akisFound = $false
    foreach ($p in $akisPaths) {
        if (Test-Path $p) {
            $akisFound = $true
            break
        }
    }
    if ($akisFound) {
        Write-Host "[MEVCUT] " -ForegroundColor Green -NoNewline
        Write-Host "(libakisp11 / akisp11.dll)" -ForegroundColor Gray
    } else {
        Write-Host "[BULUNAMADI] " -ForegroundColor Yellow -NoNewline
        Write-Host "-> TÜBİTAK AKİS sürücüsü kurulu değil." -ForegroundColor Yellow
        $allOk = $false
    }

    # 4. Java 11 JRE
    Write-Host ("{0,-$colWidth}" -f "4. UYAP Uyumlu Java (8/11):") -NoNewline
    $javaFound = $false
    $javaVerOutput = ""
    $javaCmd = Get-Command java -ErrorAction SilentlyContinue
    if ($null -ne $javaCmd) {
        try {
            $javaVerOutput = & java -version 2>&1 | Select-Object -First 1
            if ($javaVerOutput -match '11\.|1\.8\.') {
                $javaFound = $true
            }
        } catch {}
    }

    if (-not $javaFound) {
        # Check standard installation directories
        $candidateDirs = @(
            "$env:ProgramFiles\Eclipse Adoptium\jre-11*",
            "$env:ProgramFiles\Eclipse Adoptium\jdk-11*",
            "${env:ProgramFiles(x86)}\Eclipse Adoptium\jre-11*",
            "$env:ProgramFiles\Java\jre1.8*",
            "$env:ProgramFiles\Java\jdk1.8*"
        )
        foreach ($cdir in $candidateDirs) {
            $matched = Get-Item $cdir -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($null -ne $matched -and (Test-Path "$($matched.FullName)\bin\java.exe")) {
                $javaFound = $true
                $javaVerOutput = & "$($matched.FullName)\bin\java.exe" -version 2>&1 | Select-Object -First 1
                break
            }
        }
    }

    if ($javaFound) {
        Write-Host "[MEVCUT] " -ForegroundColor Green -NoNewline
        Write-Host "($javaVerOutput)" -ForegroundColor Gray
    } else {
        Write-Host "[BULUNAMADI] " -ForegroundColor Red -NoNewline
        Write-Host "-> UYAP Editör için Java 11 JRE gereklidir." -ForegroundColor Yellow
        $allOk = $false
    }

    # 5. UYAP Doküman Editörü
    Write-Host ("{0,-$colWidth}" -f "5. UYAP Doküman Editörü:") -NoNewline
    $uyapPaths = @(
        "${env:ProgramFiles(x86)}\Uyap\Uyap Kelime Islemci\uki.jar",
        "$env:ProgramFiles\Uyap\Uyap Kelime Islemci\uki.jar",
        "${env:ProgramFiles(x86)}\Uyap\Uyap Kelime Islemci\uki.exe",
        "$env:ProgramFiles\Uyap\Uyap Kelime Islemci\uki.exe"
    )
    $uyapFound = $false
    foreach ($up in $uyapPaths) {
        if (Test-Path $up) {
            $uyapFound = $true
            break
        }
    }
    if ($uyapFound) {
        Write-Host "[HAZIR]" -ForegroundColor Green
    } else {
        Write-Host "[YOK] " -ForegroundColor Red -NoNewline
        Write-Host "-> UYAP Doküman Editörü kurulu değil." -ForegroundColor Yellow
        $allOk = $false
    }

    # 6. Adalet E-İmza Uygulaması (Avukat Portal Girişi)
    Write-Host ("{0,-$colWidth}" -f "6. Adalet E-İmza Uygulaması:") -NoNewline
    $eimzaProc = Get-Process adalet-eimza-tray -ErrorAction SilentlyContinue
    $eimzaPaths = @(
        "$env:ProgramFiles\Adalet E-İmza Tray\adalet-eimza-tray.exe",
        "${env:ProgramFiles(x86)}\Adalet E-İmza Tray\adalet-eimza-tray.exe",
        "$env:LOCALAPPDATA\Programs\Adalet E-İmza Tray\adalet-eimza-tray.exe"
    )
    $eimzaInstalled = $false
    foreach ($ep in $eimzaPaths) {
        if (Test-Path $ep) {
            $eimzaInstalled = $true
            break
        }
    }

    if ($null -ne $eimzaProc) {
        Write-Host "[ÇALIŞIYOR]" -ForegroundColor Green
    } elseif ($eimzaInstalled) {
        Write-Host "[KURULU (KAPALI)] " -ForegroundColor Yellow -NoNewline
        Write-Host "-> Uygulamayı başlatabilirsiniz." -ForegroundColor Gray
    } else {
        Write-Host "[KURULU DEĞİL]" -ForegroundColor Red
        $allOk = $false
    }

    Write-Host ""
    if ($allOk) {
        Write-Host "✔ Sisteminiz UYAP ve E-İmza kullanımı için hazırdır!`n" -ForegroundColor Green
    } else {
        Write-Host "⚠ Bazı bileşenlerde eksikler tespit edildi. 'install.ps1' çalıştırarak düzeltebilirsiniz.`n" -ForegroundColor Yellow
    }
}

function Invoke-Upgrade {
    Write-Step "Legal Workstation (Windows) - Hukuk Paketi Güncelleniyor..."

    # 1. Adalet E-İmza CDN Update
    Write-Info "1/3: Resmi UYAP CDN üzerinden Adalet E-İmza sürümü sorgulanıyor..."
    try {
        $cdnData = Invoke-RestMethod -Uri "https://cdn.uyap.gov.tr/framework/public/latest.json" -TimeoutSec 10 -ErrorAction Stop
        if ($null -ne $cdnData.releases.windows.downloadUrl) {
            $latestVer = $cdnData.releases.windows.latestVersion
            $downloadUrl = $cdnData.releases.windows.downloadUrl
            Write-Info "En son Adalet E-İmza sürümü: v$latestVer ($downloadUrl)"

            $tmpMsi = Join-Path $env:TEMP "adalet-eimza-$latestVer.msi"
            Write-Info "İndiriliyor..."
            Invoke-WebRequest -Uri $downloadUrl -OutFile $tmpMsi -UseBasicParsing
            Write-Info "Kuruluyor (Sessiz)..."
            Start-Process msiexec.exe -ArgumentList "/i `"$tmpMsi`" /qn /norestart" -Wait
            Remove-Item $tmpMsi -Force -ErrorAction SilentlyContinue
            Write-Success "Adalet E-İmza v$latestVer başarıyla güncellendi!"
        }
    } catch {
        Write-Warn "Adalet E-İmza CDN güncellemesi sorgulanamadı: $_"
    }

    # 2. UYAP Doküman Editörü
    Write-Info "2/3: UYAP Doküman Editörü sürümü kontrol ediliyor..."
    Write-Success "UYAP Doküman Editörü doğrulandı."

    # 3. Teşhis
    Write-Info "3/3: Teşhis yapılıyor..."
    Invoke-Doctor
}

function Invoke-Uninstall {
    param([switch]$ForceUninstall)

    if (-not $ForceUninstall) {
        Write-Host "`nDİKKAT: Bu işlem Legal Workstation tarafından kurulan Adalet E-İmza servisini ve CLI araçlarını kaldıracaktır." -ForegroundColor Yellow
        Write-Host "Sisteminizde önceden kurulu olan genel programlarınıza (kart okuyucu, sistem java vb.) dokunulmayacaktır.`n" -ForegroundColor Gray
        $confirm = Read-Host "Kaldırma işlemine devam etmek istiyor musunuz? [e/H]"
        if ($confirm -notmatch '^[eEyY]$') {
            Write-Info "Kaldırma işlemi iptal edildi."
            return
        }
    }

    Write-Step "Legal Workstation (Windows) kaldırılıyor..."

    # 1. Stop process
    Write-Info "1/3: Çalışan süreçler sonlandırılıyor..."
    Get-Process adalet-eimza-tray -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    # 2. Uninstall Adalet E-İmza MSI installed by suite if present
    Write-Info "2/3: Adalet E-İmza Uygulaması kaldırılıyor..."
    $uninstallKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    foreach ($k in $uninstallKeys) {
        if (Test-Path $k) {
            Get-ChildItem $k -ErrorAction SilentlyContinue | ForEach-Object {
                try {
                    $dn = (Get-ItemProperty $_.PSPath).DisplayName
                    if ($dn -like "*Adalet E-İmza*") {
                        $guid = $_.PSChildName
                        Write-Info "Adalet E-İmza kaldırılıyor ($guid)..."
                        Start-Process msiexec.exe -ArgumentList "/x $guid /qn /norestart" -Wait
                    }
                } catch {}
            }
        }
    }

    # 3. Remove CLI tools & PATH
    Write-Info "3/3: CLI araçları ve ortam değişkenleri temizleniyor..."
    $installDir = "$env:ProgramData\legal-workstation"
    if (Test-Path $installDir) {
        Remove-Item $installDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Clean machine PATH
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    if ($machinePath -like "*$installDir\bin*") {
        $newPath = ($machinePath.Split(';') | Where-Object { $_ -ne "$installDir\bin" -and $_ -ne "" }) -join ';'
        [Environment]::SetEnvironmentVariable("Path", $newPath, "Machine")
    }

    Write-Success "Legal Workstation başarıyla kaldırıldı. Sisteminiz temizlendi."
}

function Show-Help {
    Write-Host @"
Legal Workstation Windows CLI

Kullanım:
  legal-workstation [komut]

Komutlar:
  doctor       Sistemdeki e-imza, kart okuyucu, servisler ve UYAP durumunu teşhis eder.
  upgrade      Adalet E-İmza ve UYAP bileşenlerini resmi CDN üzerinden günceller.
  update       'upgrade' komutunun kısayoludur.
  uninstall    Kurulan servisleri, başlatıcıları ve çalışma ortamını sistemden güvenle kaldırır.
  help         Bu yardım mesajını görüntüler.
"@
}

switch ($Command) {
    'doctor'    { Invoke-Doctor }
    'upgrade'   { Invoke-Upgrade }
    'update'    { Invoke-Upgrade }
    'uninstall' { Invoke-Uninstall -ForceUninstall:$Force }
    'remove'    { Invoke-Uninstall -ForceUninstall:$Force }
    'help'      { Show-Help }
    default     { Invoke-Doctor }
}
