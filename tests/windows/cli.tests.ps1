$ErrorActionPreference = 'Stop'
$script:failures = 0
function Check([string]$Name, [bool]$Condition) {
    if ($Condition) { Write-Host "  -> [GECTI] $Name" }
    else { Write-Host "  [HATA] $Name"; $script:failures++ }
}

$env:LW_CLI_PATH = "$env:LW_REPO_ROOT/bin/legal-workstation.ps1"

# Sabit bir sarmalayici: kendi $args'ini CLI'ye nokta-kaynak ile aktarir. Boylece
# PowerShell parametre baglama devre disi kalir ve ham bayraklar test edilir.
$probe = Join-Path $env:LW_TEST_ROOT 'cli-probe.ps1'
@'
. "$env:LW_CLI_PATH" @args
Write-Output "CMD=$script:LwCommand ALL=$script:LwAll YES=$script:LwYes"
'@ | Set-Content -LiteralPath $probe -Encoding UTF8

function Get-Parsed([string[]]$CliArgs) {
    return (& pwsh -NoProfile -File $probe @CliArgs) -join "`n"
}

Check "uninstall --all -> CMD/ALL" ((Get-Parsed @('uninstall', '--all')) -match 'CMD=uninstall ALL=True YES=False')
Check "uninstall -y -> YES" ((Get-Parsed @('uninstall', '-y')) -match 'CMD=uninstall ALL=False YES=True')
Check "uninstall --yes -> YES" ((Get-Parsed @('uninstall', '--yes')) -match 'YES=True')
Check "uninstall -Force -> YES" ((Get-Parsed @('uninstall', '-Force')) -match 'YES=True')
Check "doctor default" ((Get-Parsed @('doctor')) -match 'CMD=doctor ALL=False YES=False')
Check "bos -> doctor" ((Get-Parsed @()) -match 'CMD=doctor')

if ($script:failures -gt 0) { Write-Host "==> [BASARISIZ] $($script:failures) kontrol basarisiz."; exit 1 }
Write-Host "==> [BASARILI] Windows CLI arguman testleri gecti."
exit 0
