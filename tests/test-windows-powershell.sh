#!/usr/bin/env bash
# Automated verification test for Windows PowerShell scripts using official Microsoft PowerShell container
set -euo pipefail

DIR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Linux Legal Workstation - Windows PowerShell Sözdizimi ve Mantık Testi Başlatılıyor..."

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

        Write-Host "==> 2. CLI Help Komutu Test Ediliyor..." -ForegroundColor Cyan
        & /workspace/bin/legal-workstation.ps1 help

        Write-Host "`n==> 3. UYAP CDN Canlı Bağlantısı Test Ediliyor (PowerShell Invoke-RestMethod)..." -ForegroundColor Cyan
        $cdn = Invoke-RestMethod -Uri "https://cdn.uyap.gov.tr/framework/public/latest.json" -TimeoutSec 10
        Write-Host "  Adalet E-İmza Windows Sürümü: $($cdn.releases.windows.latestVersion)" -ForegroundColor Green
        Write-Host "  Windows İndirme Adresi: $($cdn.releases.windows.downloadUrl)" -ForegroundColor Green

        Write-Host "`n==> 4. CLI Doctor Komutu Test Ediliyor..." -ForegroundColor Cyan
        & /workspace/bin/legal-workstation.ps1 doctor
    '

echo
echo "==> [BAŞARILI] Windows PowerShell entegrasyon ve sözdizimi testi eksiksiz geçti!"
