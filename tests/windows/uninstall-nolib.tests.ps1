$ErrorActionPreference = 'Stop'

$script:failures = 0
function Check([string]$Name, [bool]$Condition) {
    if ($Condition) { Write-Host "  -> [GECTI] $Name" }
    else { Write-Host "  [HATA] $Name"; $script:failures++ }
}

# lib/manifest.ps1 olmadan (kismi ya da bozulmus kurulum): kaldirma
# "command not found" ile olmemeli, guvenli dosya temizligine dusmeli
# (Linux CLI'da bunun icin acik guvenli stub'lar var).
$stage = Join-Path $env:LW_TEST_ROOT 'nolib'
Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path (Join-Path $stage 'bin') -Force | Out-Null
Copy-Item "$env:LW_REPO_ROOT/bin/legal-workstation.ps1" -Destination (Join-Path $stage 'bin') -Force
# lib/ KASITLI olarak olusturulmaz.

$engine = $null
try { $engine = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName } catch { }
if (-not $engine) { $engine = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell.exe' } }

$env:LW_STAGE = $stage
$probe = Join-Path $stage 'probe.ps1'
@'
$env:LW_MANIFEST_DIR = Join-Path $env:LW_TEST_ROOT 'nolib-manifest'
$env:LW_PATH_SCOPE   = "Process"
. "$env:LW_STAGE/bin/legal-workstation.ps1"
foreach ($mode in @("safe", "all")) {
    try {
        if ($mode -eq "safe") { Invoke-Uninstall -AssumeYes } else { Invoke-Uninstall -Complete -AssumeYes }
        Write-Output "RESULT_$mode=completed"
    } catch {
        Write-Output "RESULT_$mode=threw:$($_.Exception.GetType().Name)"
    }
}
'@ | Set-Content -LiteralPath $probe -Encoding UTF8

$out = (& $engine -NoProfile -File $probe 2>&1) -join "`n"
Check "lib yok: guvenli 'uninstall' tamamlandi (cokmedi)" ($out -match 'RESULT_safe=completed')
Check "lib yok: 'uninstall --all' tamamlandi (cokmedi)" ($out -match 'RESULT_all=completed')
Check "lib yok: CommandNotFoundException ile olmuyor" ($out -notmatch 'CommandNotFoundException')

if ($script:failures -gt 0) { Write-Host "==> [BASARISIZ] $($script:failures) kontrol basarisiz."; exit 1 }
Write-Host "==> [BASARILI] Windows kutuphanesiz kaldirma testleri gecti."
exit 0
