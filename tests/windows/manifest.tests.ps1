$ErrorActionPreference = 'Stop'

. "$env:LW_REPO_ROOT/lib/manifest.ps1"

$env:LW_MANIFEST_DIR = Join-Path $env:LW_TEST_ROOT 'lw'
$script:failures = 0
function Check([string]$Name, [bool]$Condition) {
    if ($Condition) { Write-Host "  -> [GECTI] $Name" }
    else { Write-Host "  [HATA] $Name"; $script:failures++ }
}

Initialize-LwManifest
Check "manifest dosyasi olusturuldu" (Test-Path -LiteralPath (Get-LwManifestPath))

Add-LwManifestPackage -ProductCode @('{AAAA}', '{BBBB}')
Add-LwManifestPackage -ProductCode @('{BBBB}', '{CCCC}')
$doc = Read-LwManifest
Check "paketler tekrarsiz kaydedildi" (($doc.packages_added -join ',') -eq '{AAAA},{BBBB},{CCCC}')
Check "os_family windows" ($doc.os_family -eq 'windows')

Add-LwManifestPath -Path @('C:\suite\uets')
Add-LwManifestPath -Path @('C:\suite\uets')          # dedup
Check "path tekrarsiz kaydedildi" ((Read-LwManifest).paths.Count -eq 1)

# Bozuk JSON toparlanmali (Review Focus 3).
[System.IO.File]::WriteAllText((Get-LwManifestPath), '{ bu gecerli json degil', (New-Object System.Text.UTF8Encoding($false)))
$recovered = Read-LwManifest
Check "bozuk json toparlandi (bos liste)" ($recovered.packages_added.Count -eq 0)

Remove-LwManifestFile
Check "manifest silindi" (-not (Test-Path -LiteralPath (Get-LwManifestPath)))

if ($script:failures -gt 0) { Write-Host "==> [BASARISIZ] $($script:failures) kontrol basarisiz."; exit 1 }
Write-Host "==> [BASARILI] Windows manifest testleri gecti."
