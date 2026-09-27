# Linux Legal Workstation - Turkish Legal Workstation Windows Installer
# Repository: https://github.com/AenuHub/linux-legal-workstation

[CmdletBinding()]
param ()

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

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

function Print-Banner {
    $banner = @"
  _      _                      _                     _  __          __        _       _        _   _             
 | |    (_)                    | |                   | | \ \        / /       | |     | |      | | (_)            
 | |     _ _ __  _   ___  __   | |     ___  __ _  __ | |  \ \  /\  / /___  _ __| | _____| |_ __ _| |_ _  ___  _ __  
 | |    | | '_ \| | | \ \/ /   | |    / _ \/ _` |/ _` | |   \ \/  \/ // _ \| '__| |/ / __| __/ _` | __| |/ _ \| '_ \ 
 | |____| | | | | |_| |>  <    | |___|  __/ (_| | (_| | |    \  /\  /| (_) | |  |   <\__ \ || (_| | |_| | (_) | | | |
 |______|_|_| |_|\__,_/_/\_\   |______\___|\__, |\__,_|_|     \/  \/  \___/|_|  |_|\_\___/\__\__,_|\__|_|\___/|_| |_|
                                            __/ |                                                                     
                                           |___/                                                                      
"@
    Write-Host $banner -ForegroundColor DarkCyan
    Write-Host "========================================================================" -ForegroundColor Cyan
    Write-Host "  Türkiye Avukatları İçin Tek Komutla Windows Çalışma İstasyonu Kurulumu" -ForegroundColor White
    Write-Host "========================================================================`n" -ForegroundColor Cyan
}

# 0. Check Administrator Privileges
function Ensure-Admin {
    $isAdmin = $false
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]$identity
        $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {}

    if (-not $isAdmin) {
        if ($MyInvocation.MyCommand.Path) {
            Write-Info "Kurulum için Yönetici (Administrator) yetkisi gerekiyor. PowerShell yükseltiliyor..."
            Start-Process powershell.exe -ArgumentList ("-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`"") -Verb RunAs
            exit
        } else {
            Write-Failure "Bu kurulum aracını çalıştırmak için lütfen PowerShell'i 'Yönetici Olarak Çalıştır' seçeneğiyle açınız."
            exit 1
        }
    }
}

# 1. Enable & Start Smart Card Service (SCardSvr)
function Install-SmartCardService {
    Write-Step "1/5: Windows Akıllı Kart Servisi (SCardSvr) yapılandırılıyor..."
    try {
        if (Get-Command Set-Service -ErrorAction SilentlyContinue) {
            Set-Service -Name SCardSvr -StartupType Automatic -ErrorAction SilentlyContinue
            Start-Service -Name SCardSvr -ErrorAction SilentlyContinue
        }
        Write-Success "Windows Akıllı Kart Servisi (SCardSvr) otomatik başlatmaya ayarlandı ve çalıştırıldı."
    } catch {
        Write-Warn "Akıllı Kart servisi yapılandırılırken uyarı alındı: $_"
    }
}

# 2. Install Eclipse Temurin Java 11 JRE
function Install-Java11 {
    Write-Step "2/5: UYAP Uyumlu Java 11 JRE ortamı kontrol ediliyor..."
    
    $javaFound = $false
    try {
        $jver = & java -version 2>&1 | Select-Object -First 1
        if ($jver -match '11\.|1\.8\.') {
            $javaFound = $true
            Write-Info "Uyumlu Java zaten mevcut: $jver"
        }
    } catch {}

    if (-not $javaFound) {
        Write-Info "Resmi Adoptium Eclipse Temurin Java 11 JRE indiriliyor..."
        $jreUrl = "https://api.adoptium.net/v3/installer/latest/11/ga/windows/x64/jre/hotspot/normal/eclipse"
        $tmpMsi = Join-Path $env:TEMP "temurin-11-jre.msi"
        
        try {
            Invoke-WebRequest -Uri $jreUrl -OutFile $tmpMsi -UseBasicParsing
            Write-Info "Java 11 JRE kuruluyor (Sessiz kurulum)..."
            $p = Start-Process msiexec.exe -ArgumentList "/i `"$tmpMsi`" /qn /norestart ADDLOCAL=FeatureMain,FeatureJavaHome,FeatureJarFileRunWith" -Wait -PassThru
            Remove-Item $tmpMsi -Force -ErrorAction SilentlyContinue
            
            # Refresh PATH for current session
            $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
            $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
            $env:Path = "$machinePath;$userPath"
            
            Write-Success "Eclipse Temurin Java 11 JRE başarıyla kuruldu."
        } catch {
            Write-Failure "Java 11 JRE kurulumu başarısız oldu: $_"
        }
    }
}

# 3. Install TÜBİTAK AKİS / AKİA Smart Card Driver
function Install-AkisDriver {
    Write-Step "3/5: TÜBİTAK AKİS / AKİA (libakisp11) akıllı kart sürücüsü kuruluyor..."

    $akisInstalled = $false
    $testPaths = @(
        "$env:ProgramFiles\Akis\akisp11.dll",
        "$env:ProgramFiles\Akia\akisp11.dll",
        "$env:SystemRoot\System32\akisp11.dll",
        "${env:ProgramFiles(x86)}\Akis\akisp11.dll",
        "${env:ProgramFiles(x86)}\Akia\akisp11.dll"
    )
    foreach ($tp in $testPaths) {
        if (Test-Path $tp) {
            $akisInstalled = $true
            break
        }
    }

    if ($akisInstalled) {
        Write-Info "TÜBİTAK AKİS sürücüsü zaten sistemde kurulu."
    } else {
        $akisZipUrl = "https://akiskart.bilgem.tubitak.gov.tr/wp-content/uploads/sites/33/2026/06/Akia_windows-x64_6_8_10.msi_.zip"
        $tmpZip = Join-Path $env:TEMP "akia-win64.zip"
        $extractDir = Join-Path $env:TEMP "akia-extract"

        try {
            Write-Info "Resmi TÜBİTAK BILGEM sunucusundan AKİS x64 paketi indiriliyor..."
            Invoke-WebRequest -Uri $akisZipUrl -OutFile $tmpZip -UseBasicParsing
            
            if (Test-Path $extractDir) {
                Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue
            }
            Expand-Archive -Path $tmpZip -DestinationPath $extractDir -Force
            
            $msiFile = Get-ChildItem -Path $extractDir -Filter "*.msi" -Recurse | Select-Object -First 1
            if ($null -ne $msiFile) {
                Write-Info "TÜBİTAK AKİS / AKİA kuruluyor ($($msiFile.Name))..."
                Start-Process msiexec.exe -ArgumentList "/i `"$($msiFile.FullName)`" /qn /norestart" -Wait
                Write-Success "TÜBİTAK AKİS sürücüsü ve AKİA başarıyla kuruldu."
            } else {
                Write-Warn "AKİS ZIP içinde MSI paketi bulunamadı."
            }

            Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue
            Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue
        } catch {
            Write-Failure "TÜBİTAK AKİS sürücüsü kurulurken hata oluştu: $_"
        }
    }
}

# 4. Install UYAP Doküman Editörü
function Install-UyapEditor {
    Write-Step "4/5: UYAP Doküman Editörü yapılandırılıyor..."

    $uyapInstalled = $false
    $testPaths = @(
        "${env:ProgramFiles(x86)}\Uyap\Uyap Kelime Islemci\uki.jar",
        "$env:ProgramFiles\Uyap\Uyap Kelime Islemci\uki.jar",
        "${env:ProgramFiles(x86)}\Uyap\Uyap Kelime Islemci\uki.exe",
        "$env:ProgramFiles\Uyap\Uyap Kelime Islemci\uki.exe"
    )
    foreach ($up in $testPaths) {
        if (Test-Path $up) {
            $uyapInstalled = $true
            break
        }
    }

    if ($uyapInstalled) {
        Write-Info "UYAP Doküman Editörü sistemde mevcut."
    } else {
        $uyapMsiUrl = "https://rayp.adalet.gov.tr/resimler/2/dosya/UKI_V5.4.20.msi"
        $tmpMsi = Join-Path $env:TEMP "uyap-editor.msi"

        try {
            Write-Info "Resmi UYAP sunucusundan Doküman Editörü indiriliyor..."
            Invoke-WebRequest -Uri $uyapMsiUrl -OutFile $tmpMsi -UseBasicParsing
            
            Write-Info "UYAP Doküman Editörü kuruluyor..."
            Start-Process msiexec.exe -ArgumentList "/i `"$tmpMsi`" /qn /norestart" -Wait
            Remove-Item $tmpMsi -Force -ErrorAction SilentlyContinue
            Write-Success "UYAP Doküman Editörü başarıyla kuruldu."
        } catch {
            Write-Failure "UYAP Doküman Editörü kurulurken hata oluştu: $_"
        }
    }
}

# 5. Install Adalet E-İmza Uygulaması (Avukat Portal Girişi)
function Install-AdaletEimza {
    Write-Step "5/5: Adalet E-İmza Uygulaması (Avukat Portal Girişi) kuruluyor..."

    try {
        Write-Info "Resmi UYAP CDN üzerinden son Adalet E-İmza sürümü sorgulanıyor..."
        $cdnData = Invoke-RestMethod -Uri "https://cdn.uyap.gov.tr/framework/public/latest.json" -TimeoutSec 10
        $downloadUrl = $cdnData.releases.windows.downloadUrl
        $latestVer = $cdnData.releases.windows.latestVersion

        if ($null -ne $downloadUrl) {
            Write-Info "Sürüm: v$latestVer indiriliyor ($downloadUrl)..."
            $tmpMsi = Join-Path $env:TEMP "adalet-eimza-install.msi"
            Invoke-WebRequest -Uri $downloadUrl -OutFile $tmpMsi -UseBasicParsing

            Write-Info "Adalet E-İmza kuruluyor..."
            Start-Process msiexec.exe -ArgumentList "/i `"$tmpMsi`" /qn /norestart" -Wait
            Remove-Item $tmpMsi -Force -ErrorAction SilentlyContinue
            Write-Success "Adalet E-İmza Uygulaması v$latestVer kuruldu."

            # Start the tray application
            $trayExe = @(
                "$env:ProgramFiles\Adalet E-İmza Tray\adalet-eimza-tray.exe",
                "${env:ProgramFiles(x86)}\Adalet E-İmza Tray\adalet-eimza-tray.exe",
                "$env:LOCALAPPDATA\Programs\Adalet E-İmza Tray\adalet-eimza-tray.exe"
            ) | Where-Object { Test-Path $_ } | Select-Object -First 1

            if ($null -ne $trayExe) {
                Start-Process -FilePath $trayExe -ErrorAction SilentlyContinue
                Write-Success "Adalet E-İmza sistem tepsisi (tray) servisi başlatıldı."
            }
        }
    } catch {
        Write-Warn "Adalet E-İmza CDN üzerinden kurulurken uyarı alındı: $_"
    }
}

# 6. Install TÜRKTRUST / BaroKart PALMA Smart Card Management (PIN & Blokaj)
function Install-Palma {
    Write-Step "6/7: TÜRKTRUST / BaroKart PALMA (PIN & Blokaj Yönetimi) kuruluyor..."

    $palmaInstalled = $false
    $palmaPaths = @(
        "$env:ProgramFiles\TURKTRUST\Palma\PALMA.exe",
        "${env:ProgramFiles(x86)}\TURKTRUST\Palma\PALMA.exe"
    )
    foreach ($p in $palmaPaths) {
        if (Test-Path $p) {
            $palmaInstalled = $true
            break
        }
    }

    if ($palmaInstalled) {
        Write-Info "PALMA akıllı kart yönetim uygulaması zaten kurulu."
    } else {
        $palmaUrl = "https://e-imza.barobirlik.org.tr/program/PALMA_2.9_64bit_Setup_A2.7_G10.8_b24020501.exe"
        $tmpPalma = Join-Path $env:TEMP "Palma_Setup.exe"

        try {
            Write-Info "Resmi TBB sunucusundan PALMA kurulum paketi indiriliyor..."
            Invoke-WebRequest -Uri $palmaUrl -OutFile $tmpPalma -UseBasicParsing
            Write-Info "PALMA kuruluyor (Sessiz kurulum)..."
            Start-Process -FilePath $tmpPalma -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART" -Wait
            Remove-Item $tmpPalma -Force -ErrorAction SilentlyContinue
            Write-Success "PALMA (PIN oluşturma ve blokaj kaldırma aracı) başarıyla kuruldu."
        } catch {
            Write-Warn "PALMA kurulurken uyarı alındı: $_"
        }
    }
}

# 7. Install PTT UETS E-İmza Client
function Install-Uets {
    Write-Step "7/7: PTT UETS (Ulusal Elektronik Tebligat Sistemi) E-İmza İstemcisi kuruluyor..."

    $uetsDir = Join-Path $env:ProgramFiles "PTT\UETS"
    $uetsJar = Join-Path $uetsDir "uets-eimza.jar"
    $uetsUrl = "https://api.etebligat.gov.tr/v1/auth/_eimza/uets-eimza.jar"

    try {
        if (-not (Test-Path $uetsDir)) {
            New-Item -Path $uetsDir -ItemType Directory -Force | Out-Null
        }

        Write-Info "Resmi PTT UETS sunucusundan uets-eimza.jar indiriliyor..."
        Invoke-WebRequest -Uri $uetsUrl -OutFile $uetsJar -UseBasicParsing

        # Create Start Menu shortcut
        if ($PSVersionTable.Platform -ne 'Unix') {
            try {
                $shell = New-Object -ComObject WScript.Shell
                $shortcutPath = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\PTT UETS E-İmza.lnk"
                $shortcut = $shell.CreateShortcut($shortcutPath)
                
                $javawCmd = Get-Command javaw.exe -ErrorAction SilentlyContinue
                $javawPath = if ($javawCmd) { $javawCmd.Source } else { "javaw.exe" }
                
                $shortcut.TargetPath = $javawPath
                $shortcut.Arguments = "-jar `"$uetsJar`""
                $shortcut.WorkingDirectory = $uetsDir
                $shortcut.Description = "PTT Ulusal Elektronik Tebligat Sistemi E-İmza Uygulaması"
                $shortcut.Save()
            } catch {}
        }

        Write-Success "PTT UETS E-İmza İstemcisi kuruldu ve Başlat Menüsüne eklendi."
    } catch {
        Write-Warn "PTT UETS istemcisi kurulurken uyarı alındı: $_"
    }
}

# 8. Install CLI Tools & Add to PATH
function Setup-CliTools {
    $installDir = "$env:ProgramData\legal-workstation\bin"
    if (-not (Test-Path $installDir)) {
        New-Item -Path $installDir -ItemType Directory -Force | Out-Null
    }

    $repoUrl = "https://raw.githubusercontent.com/AenuHub/linux-legal-workstation/main"
    $scriptDir = $PSScriptRoot

    if ($scriptDir -and (Test-Path "$scriptDir\bin\legal-workstation.ps1")) {
        Copy-Item "$scriptDir\bin\legal-workstation.ps1" -Destination "$installDir\legal-workstation.ps1" -Force
        Copy-Item "$scriptDir\bin\legal-workstation.cmd" -Destination "$installDir\legal-workstation.cmd" -Force
    } else {
        Invoke-WebRequest -Uri "$repoUrl/bin/legal-workstation.ps1" -OutFile "$installDir\legal-workstation.ps1" -UseBasicParsing
        Invoke-WebRequest -Uri "$repoUrl/bin/legal-workstation.cmd" -OutFile "$installDir\legal-workstation.cmd" -UseBasicParsing
    }

    # Add to Machine PATH if not present
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    if ($machinePath -notlike "*$installDir*") {
        [Environment]::SetEnvironmentVariable("Path", "$machinePath;$installDir", "Machine")
        $env:Path = "$env:Path;$installDir"
        Write-Success "'legal-workstation' komutu sistem PATH ortamına eklendi."
    }
}

function Main {
    Print-Banner
    Ensure-Admin
    Install-SmartCardService
    Install-Java11
    Install-AkisDriver
    Install-UyapEditor
    Install-AdaletEimza
    Install-Palma
    Install-Uets
    Setup-CliTools

    Write-Step "Kurulum Tamamlandı! Teşhis ve Doğrulama Yapılıyor..."
    $cliScript = "$env:ProgramData\legal-workstation\bin\legal-workstation.ps1"
    if (Test-Path $cliScript) {
        & $cliScript doctor
    }

    Write-Host "`nTebrikler! Windows Hukuk Çalışma İstasyonu başarıyla kuruldu." -ForegroundColor Green
    Write-Host "İstediğiniz zaman terminalden veya PowerShell'den 'legal-workstation doctor' çalıştırabilirsiniz.`n" -ForegroundColor Cyan
}

Main

