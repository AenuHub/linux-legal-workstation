$ErrorActionPreference = 'Stop'

. "$env:LW_REPO_ROOT/lib/manifest.ps1"

$env:LW_MANIFEST_DIR = Join-Path $env:LW_TEST_ROOT 'record'
Remove-Item -LiteralPath $env:LW_MANIFEST_DIR -Recurse -Force -ErrorAction SilentlyContinue

$script:failures = 0
function Check([string]$Name, [bool]$Condition) {
    if ($Condition) { Write-Host "  -> [GECTI] $Name" }
    else { Write-Host "  [HATA] $Name"; $script:failures++ }
}

# Sahte kayit defteri + msiexec kurulum stub'i: stub, "kurulum" sirasinda YENI bir
# urun kodu ekler. Boylece Install-LwMsi'nin yalnizca YENI ekleneni kaydettigini
# gercekten (registry/msiexec olmadan) dogrulariz.
$regFile = Join-Path $env:LW_TEST_ROOT 'reg-keys.txt'
Set-Content -LiteralPath $regFile -Value '{OLD-PREEXISTING}' -Encoding UTF8

$stub = Join-Path $env:LW_TEST_ROOT 'msiexec-install-stub.ps1'
@'
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest)
Add-Content -LiteralPath $env:LW_REG_KEYS_FILE -Value '{NEW-SUITE}'
exit 0
'@ | Set-Content -LiteralPath $stub -Encoding UTF8

$env:LW_REG_KEYS_FILE = $regFile
$env:LW_MSIEXEC      = $stub

$new = @(Install-LwMsi -MsiPath 'C:\tmp\suite.msi')
$doc = Read-LwManifest
Check "Install-LwMsi yeni urun kodunu dondurdu" (($new.Count -eq 1) -and ($new[0] -eq '{NEW-SUITE}'))
Check "manifestoya yalnizca YENI urun kodu kaydedildi" (($doc.packages_added -join ',') -eq '{NEW-SUITE}')
Check "onceden kurulu urun kodu kaydedilmedi" ($doc.packages_added -notcontains '{OLD-PREEXISTING}')

# Idempotent: ayni urun kodu ikinci kez kaydedilmemeli.
Install-LwMsi -MsiPath 'C:\tmp\suite.msi' | Out-Null
Check "ayni urun kodu tekrar kaydedilmiyor" ((Read-LwManifest).packages_added.Count -eq 1)

if ($script:failures -gt 0) { Write-Host "==> [BASARISIZ] $($script:failures) kontrol basarisiz."; exit 1 }
Write-Host "==> [BASARILI] Windows MSI kayit testleri gecti."
exit 0
