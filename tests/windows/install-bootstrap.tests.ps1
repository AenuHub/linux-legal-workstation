$ErrorActionPreference = 'Stop'

$script:failures = 0
function Check([string]$Name, [bool]$Condition) {
    if ($Condition) { Write-Host "  -> [GECTI] $Name" }
    else { Write-Host "  [HATA] $Name"; $script:failures++ }
}

# install.ps1'in manifest kutuphanesi bootstrap blogunu (metin olarak) cikar.
$raw = Get-Content -Raw "$env:LW_REPO_ROOT/install.ps1"
$pattern = '(?s)\$script:LwRepoUrl = ''https://raw\.githubusercontent\.com/AenuHub/linux-legal-workstation/main''.*?\. \$script:LwLibPath'
$m = [regex]::Match($raw, $pattern)
Check "install.ps1 bootstrap blogu bulundu" ($m.Success)
if (-not $m.Success) { Write-Host "==> [BASARISIZ] bootstrap blogu bulunamadi."; exit 1 }
$block = $m.Value

$engine = $null
try { $engine = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName } catch { }
if (-not $engine) { $engine = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell.exe' } }

# --- A) 'irm | iex' akisi: $PSScriptRoot BOS olur (Invoke-Expression bunu boyle verir). ---
# Ag erisimi olmadan calisabilmesi icin gecici yolda kutuphane birak.
$tempLib = Join-Path ([System.IO.Path]::GetTempPath()) 'lw-manifest.ps1'
Copy-Item "$env:LW_REPO_ROOT/lib/manifest.ps1" -Destination $tempLib -Force

$threw = $null
try { Invoke-Expression $block } catch { $threw = $_ }
Check "irm|iex: bootstrap hata vermemeli (bos PSScriptRoot)" ($null -eq $threw)
if ($threw) { Write-Host "        hata: $($threw.Exception.Message)" }
Check "irm|iex: kutuphane gecici yoldan yuklendi" ($script:LwLibPath -eq $tempLib)
Check "irm|iex: manifest fonksiyonlari tanimli" ([bool](Get-Command Read-LwManifest -ErrorAction SilentlyContinue))

# --- B) Depo duzeni: $PSScriptRoot dolu -> yerel lib kullanilir, indirme yok. ---
$stage = Join-Path $env:LW_TEST_ROOT 'repo-layout'
New-Item -ItemType Directory -Path (Join-Path $stage 'lib') -Force | Out-Null
Copy-Item "$env:LW_REPO_ROOT/lib/manifest.ps1" -Destination (Join-Path $stage 'lib/manifest.ps1') -Force
$footer = 'Write-Output "LIB=$script:LwLibPath"'
Set-Content -LiteralPath (Join-Path $stage 'bootstrap.ps1') `
    -Value ($block + "`n" + $footer) -Encoding UTF8
$out = (& $engine -NoProfile -File (Join-Path $stage 'bootstrap.ps1')) -join "`n"
$expected = Join-Path $stage 'lib/manifest.ps1'
Check "depo duzeni: yerel lib kullanildi (indirme yok)" ($out -match [regex]::Escape("LIB=$expected"))

if ($script:failures -gt 0) { Write-Host "==> [BASARISIZ] $($script:failures) kontrol basarisiz."; exit 1 }
Write-Host "==> [BASARILI] Windows install bootstrap testleri gecti."
exit 0
