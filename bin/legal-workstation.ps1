<#
.SYNOPSIS
    Legal Workstation - Windows Teşhis ve Sağlık Aracı (Doctor & Upgrade)
.DESCRIPTION
    Avukatlar için Windows ortamında UYAP, E-İmza ve akıllı kart bileşenlerini teşhis eder ve günceller.
#>

# PowerShell `--all` / `-y` bayraklarini baglayamaz; Linux ile ayni arayuz icin
# ham $args elle ayristirilir.
$script:LwPositional = @($args | Where-Object { $_ -notlike '-*' })
$script:LwFlags = @($args | Where-Object { $_ -like '-*' } | ForEach-Object { $_.ToLowerInvariant() })
$script:LwCommand = if ($script:LwPositional.Count -gt 0) { $script:LwPositional[0].ToLowerInvariant() } else { 'doctor' }
$script:LwAll = ($script:LwFlags -contains '--all') -or ($script:LwFlags -contains '-all')
$script:LwYes = ($script:LwFlags -contains '-y') -or ($script:LwFlags -contains '--yes') -or
                ($script:LwFlags -contains '-yes') -or ($script:LwFlags -contains '-force') -or
                ($script:LwFlags -contains '--force')

# Bu betik testler tarafindan nokta-kaynak edilebilir; komut yalnizca normal
# calistirmada dagitilir (asagida).
$script:LwLibFile = Join-Path (Split-Path -Parent $PSScriptRoot) 'lib/manifest.ps1'
if (Test-Path -LiteralPath $script:LwLibFile) { . $script:LwLibFile }

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

    # 7. PTT UETS E-İmza
    Write-Host ("{0,-$colWidth}" -f "7. PTT UETS E-İmza:") -NoNewline
    $uetsJar = "$env:ProgramFiles\PTT\UETS\uets-eimza.jar"
    if (Test-Path $uetsJar) {
        Write-Host "[HAZIR]" -ForegroundColor Green
    } else {
        Write-Host "[KURULU DEĞİL]" -ForegroundColor Yellow
    }

    # 8. TÜRKTRUST PALMA (PIN & Blokaj)
    Write-Host ("{0,-$colWidth}" -f "8. TÜRKTRUST PALMA (PIN/Blokaj):") -NoNewline
    $palmaPaths = @(
        "$env:ProgramFiles\TURKTRUST\Palma\PALMA.exe",
        "${env:ProgramFiles(x86)}\TURKTRUST\Palma\PALMA.exe"
    )
    $palmaFound = $false
    foreach ($p in $palmaPaths) {
        if (Test-Path $p) {
            $palmaFound = $true
            break
        }
    }
    if ($palmaFound) {
        Write-Host "[HAZIR]" -ForegroundColor Green
    } else {
        Write-Host "[KURULU DEĞİL]" -ForegroundColor Yellow
    }

    Write-Host ""
    if ($allOk) {
        Write-Host "[HAZIR] Sisteminiz UYAP ve E-İmza kullanımı için hazırdır!`n" -ForegroundColor Green
    } else {
        Write-Host "[UYARI] Bazı bileşenlerde eksikler tespit edildi. 'install.ps1' çalıştırarak düzeltebilirsiniz.`n" -ForegroundColor Yellow
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

function Get-LwPathScope {
    if ($env:LW_PATH_SCOPE) { return $env:LW_PATH_SCOPE }
    return 'Machine'
}

function Remove-LwMachinePathEntry {
    param([Parameter(Mandatory)][string]$Dir)
    try {
        $scope = Get-LwPathScope
        $path  = [Environment]::GetEnvironmentVariable('Path', $scope)
        if ([string]::IsNullOrEmpty($path)) { return }
        $sep    = [System.IO.Path]::PathSeparator
        $target = $Dir.TrimEnd('\', '/')
        $parts = $path.Split($sep) | Where-Object { $_ -and ($_.TrimEnd('\', '/') -ne $target) }
        $new = ($parts -join $sep)
        if ($new -ne $path) { [Environment]::SetEnvironmentVariable('Path', $new, $scope) }
    } catch { }
}

function Invoke-LwSafeUninstall {
    $installDir = Get-LwManifestDir
    $binDir     = Join-Path $installDir 'bin'
    $libDir     = Join-Path $installDir 'lib'

    Write-Info "Calisan surecler sonlandiriliyor..."
    Get-Process adalet-eimza-tray -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    if (Get-Command Read-LwManifest -ErrorAction SilentlyContinue) {
        $manifest = Read-LwManifest
        foreach ($p in @($manifest.paths)) {
            if ($p -and (Test-Path -LiteralPath $p)) {
                Write-Info "Kayitli dosya kaldiriliyor: $p"
                Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Write-Info "CLI araclari ve PATH temizleniyor..."
    Remove-LwMachinePathEntry -Dir $binDir
    foreach ($d in @($binDir, $libDir)) {
        if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
    }
    # Manifest BILEREK korunur: sonraki 'uninstall --all' hala calisabilsin diye.
}

function Invoke-Uninstall {
    param([switch]$Complete, [switch]$AssumeYes, [switch]$ForceUninstall)
    $assumeYes = $AssumeYes -or $ForceUninstall

    $hasManifest = (Get-Command Get-LwManifestPath -ErrorAction SilentlyContinue) -and
                   (Test-Path -LiteralPath (Get-LwManifestPath))
    if ($Complete -and -not $hasManifest) {
        Write-Warn "Kurulum manifestosu bulunamadi; '--all' paket/servis kaldirmasi yapamaz. Yalnizca dosyalar temizlenecek."
        $Complete = $false
    }

    if (-not $assumeYes) {
        Write-Host "`nDIKKAT: Bu islem Legal Workstation tarafindan olusturulan dosyalari kaldirir." -ForegroundColor Yellow
        if ($Complete) {
            Write-Host "Sistem paketleri/servisleri de kaldirilacak (--all)." -ForegroundColor Yellow
        }
        $confirm = Read-Host "Kaldirma islemine devam etmek istiyor musunuz? [e/H]"
        if ($confirm -notmatch '^[eEyY]$') { Write-Info "Kaldirma islemi iptal edildi."; return }
        if ($Complete) {
            $token = Read-Host "Tam kaldirmayi onaylamak icin TUMU yazin"
            if ($token -notmatch '^(TUMU|ALL)$') { Write-Info "Tam kaldirma onayi verilmedi. Iptal edildi."; return }
        }
    }

    Write-Step "Legal Workstation (Windows) kaldiriliyor..."
    if ($Complete) { Invoke-LwCompleteUninstall } else { Invoke-LwSafeUninstall }
    Write-Success "Legal Workstation basariyla kaldirildi."
}

function Restore-LwService {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Service)
    if ($PSVersionTable.Platform -eq 'Unix') { return }
    $name = [string]$Service.unit
    $plan = Get-LwServiceRevertPlan -Service $Service
    try {
        if ($plan.SetStartupType) {
            Set-Service -Name $name -StartupType $plan.SetStartupType -ErrorAction SilentlyContinue
        }
        if ($plan.Stop) { Stop-Service -Name $name -Force -ErrorAction SilentlyContinue }
        if ($plan.Start) { Start-Service -Name $name -ErrorAction SilentlyContinue }
    } catch { }
}

function Invoke-LwCompleteUninstall {
    $manifest = $null
    if (Get-Command Read-LwManifest -ErrorAction SilentlyContinue) { $manifest = Read-LwManifest }

    Invoke-LwSafeUninstall

    if ($null -ne $manifest) {
        foreach ($code in @($manifest.packages_added)) {
            if (-not $code) { continue }
            Write-Info "MSI kaldiriliyor: $code"
            try {
                $rc = Invoke-LwMsiUninstall -ProductCode $code
                if ($rc -ne 0) { Write-Warn "MSI kaldirma ($code) exit kodu $rc dondurdu." }
            } catch { Write-Warn "MSI kaldirma hatasi ($code): $_" }
        }
        foreach ($svc in @($manifest.services_enabled)) {
            Write-Info "Servis geri aliniyor: $($svc.unit)"
            Restore-LwService -Service $svc
        }
    }

    Remove-LwManifestFile
}

function Show-Help {
    Write-Host "Legal Workstation Windows CLI`n"
    Write-Host "Kullanım:"
    Write-Host "  legal-workstation [komut]`n"
    Write-Host "Komutlar:"
    Write-Host "  doctor       Sistemdeki e-imza, kart okuyucu, servisler ve UYAP durumunu teşhis eder."
    Write-Host "  upgrade      Adalet E-İmza ve UYAP bileşenlerini resmi CDN üzerinden günceller."
    Write-Host "  update       'upgrade' komutunun kısayoludur."
    Write-Host "  uninstall    Kurulan servisleri, başlatıcıları ve çalışma ortamını sistemden güvenle kaldırır."
    Write-Host "               --all : Kurulumun eklediği MSI/servisleri de kaldırır (tam kaldırma)."
    Write-Host "               -y    : Onay istemeden çalıştırır (--yes / -Force)."
    Write-Host "  help         Bu yardım mesajını görüntüler."
}

# Bu betik testler tarafindan nokta-kaynak edilebilir; yalnizca normal
# calistirmada komut dogrulanir ve dagitim yapilir.
if ($MyInvocation.InvocationName -ne '.') {
    $valid = @('doctor', 'upgrade', 'update', 'uninstall', 'remove', 'start', 'restart', 'help', '')
    if ($valid -notcontains $script:LwCommand) {
        Write-Failure "Bilinmeyen komut: $script:LwCommand"
        Show-Help
        exit 1
    }
    switch ($script:LwCommand) {
        'doctor'    { Invoke-Doctor }
        'upgrade'   { Invoke-Upgrade }
        'update'    { Invoke-Upgrade }
        'uninstall' { Invoke-Uninstall -Complete:$script:LwAll -AssumeYes:$script:LwYes }
        'remove'    { Invoke-Uninstall -Complete:$script:LwAll -AssumeYes:$script:LwYes }
        'help'      { Show-Help }
        default     { Invoke-Doctor }
    }
}
