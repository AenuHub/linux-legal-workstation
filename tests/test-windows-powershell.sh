#!/usr/bin/env bash
# Automated verification test for Windows PowerShell scripts using official Microsoft PowerShell container
set -euo pipefail

DIR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Legal Workstation - Windows PowerShell Sözdizimi ve Mantık Testi Başlatılıyor..."

docker run --rm \
    -v "$DIR_ROOT:/workspace" \
    -w /workspace \
    mcr.microsoft.com/powershell:latest \
    pwsh -NoProfile -Command '
        $ErrorActionPreference = "Stop"
        Write-Host "==> 1. PowerShell Script Sözdizimi Analizi..." -ForegroundColor Cyan

        $scripts = @("/workspace/install.ps1", "/workspace/bin/legal-workstation.ps1")
        foreach ($s in $scripts) {
            Write-Host "Denetleniyor: $s"
            $tokens = $null
            $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile($s, [ref]$tokens, [ref]$errors) | Out-Null
            if ($errors.Count -gt 0) {
                Write-Error "Sözdizimi hatası bulundu: $s"
                $errors | ForEach-Object { Write-Error $_ }
                exit 1
            }
            Write-Host "  -> [GEÇTİ] Sözdizimi hatasız." -ForegroundColor Green
        }

        Write-Host "==> 1b. install.ps1 kayit entegrasyonu dogrulaniyor..." -ForegroundColor Cyan
        $installText = Get-Content -Raw /workspace/install.ps1
        foreach ($needle in @("Initialize-LwManifest", "Add-LwManifestService", "Add-LwManifestCreatedPath", "Install-LwMsi", "Get-LwManifestDir")) {
            if ($installText -notmatch [regex]::Escape($needle)) {
                Write-Error "install.ps1 eksik: $needle"; exit 1
            }
        }
        Write-Host "  -> [GECTI] install.ps1 gerekli manifest cagrilarini iceriyor." -ForegroundColor Green

        # Onceden var olan kisayol/dosya sahiplenilmemeli (Add-LwManifestCreatedPath).
        if ($installText -notmatch [regex]::Escape("Add-LwManifestCreatedPath -Path `$shortcutPath -Existed `$hadShortcut")) {
            Write-Error "install.ps1 onceden var olan UETS kisayolunu sahipleniyor olabilir"; exit 1
        }
        Write-Host "  -> [GECTI] install.ps1 yalnizca olusturdugu kisayolu kaydediyor." -ForegroundColor Green

        Write-Host "==> 1c. CLI MSI kurulum kaydi dogrulaniyor..." -ForegroundColor Cyan
        $cliText = Get-Content -Raw /workspace/bin/legal-workstation.ps1
        if ($cliText -notmatch [regex]::Escape("Install-LwMsi")) {
            Write-Error "bin/legal-workstation.ps1 eksik: Install-LwMsi"; exit 1
        }
        if ($cliText -match "Start-Process msiexec\.exe") {
            Write-Error "bin/legal-workstation.ps1 dogrudan msiexec ile MSI kuruyor (manifest kaydi disinda)"; exit 1
        }
        Write-Host "  -> [GECTI] CLI MSI kurulumlari manifest kayit yolundan geciyor." -ForegroundColor Green

        Write-Host "==> 1d. Eski (manifestosuz) kurulum davranisi dokumante mi..." -ForegroundColor Cyan
        $readmeText = Get-Content -Raw /workspace/README.md
        if ($readmeText -notmatch [regex]::Escape("manifest yoktur")) {
            Write-Error "README.md eski (manifestosuz) kurulum notunu icermiyor"; exit 1
        }
        $changelogText = Get-Content -Raw /workspace/CHANGELOG.md
        if ($changelogText -notmatch [regex]::Escape("no back-fill")) {
            Write-Error "CHANGELOG.md eski (manifestosuz) kurulum notunu icermiyor"; exit 1
        }
        Write-Host "  -> [GECTI] Eski kurulum davranisi dokumante edilmis." -ForegroundColor Green

        Write-Host "==> 2. CLI Help Komutu Test Ediliyor..." -ForegroundColor Cyan
        & /workspace/bin/legal-workstation.ps1 help

        Write-Host "`n==> 3. UYAP CDN Canlı Bağlantısı Test Ediliyor (PowerShell Invoke-RestMethod)..." -ForegroundColor Cyan
        $cdn = Invoke-RestMethod -Uri "https://cdn.uyap.gov.tr/framework/public/latest.json" -TimeoutSec 10
        Write-Host "  Adalet E-İmza Windows Sürümü: $($cdn.releases.windows.latestVersion)" -ForegroundColor Green
        Write-Host "  Windows İndirme Adresi: $($cdn.releases.windows.downloadUrl)" -ForegroundColor Green

        Write-Host "`n==> 4. PTT UETS ve TBB PALMA İndirme Bağlantıları Test Ediliyor..." -ForegroundColor Cyan
        $uetsUrl = "https://api.etebligat.gov.tr/v1/auth/_eimza/uets-eimza.jar"
        $palmaUrl = "https://e-imza.barobirlik.org.tr/program/PALMA_2.9_64bit_Setup_A2.7_G10.8_b24020501.exe"
        
        $uetsResp = Invoke-WebRequest -Uri $uetsUrl -Headers @{ "Range" = "bytes=0-1024" } -TimeoutSec 10 -UseBasicParsing
        Write-Host "  PTT UETS İstemci HTTP Durumu: $($uetsResp.StatusCode)" -ForegroundColor Green
        
        $palmaResp = Invoke-WebRequest -Uri $palmaUrl -Method Head -TimeoutSec 10 -UseBasicParsing
        Write-Host "  TBB PALMA Kurulum HTTP Durumu: $($palmaResp.StatusCode)" -ForegroundColor Green

        Write-Host "`n==> 5. CLI Doctor Komutu Test Ediliyor..." -ForegroundColor Cyan
        & /workspace/bin/legal-workstation.ps1 doctor
    '

echo
echo "==> [BAŞARILI] Windows PowerShell entegrasyon ve sözdizimi testi başarıyla tamamlandı!"


