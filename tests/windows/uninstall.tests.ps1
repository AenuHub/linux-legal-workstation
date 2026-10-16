$ErrorActionPreference = 'Stop'

$env:LW_MANIFEST_DIR = Join-Path $env:LW_TEST_ROOT 'lw'
$env:LW_PATH_SCOPE   = 'Process'
$env:LW_MSIEXEC      = Join-Path $env:LW_REPO_ROOT 'tests/windows/msiexec-stub.ps1'
$env:LW_MSIEXEC_LOG  = Join-Path $env:LW_TEST_ROOT 'msi.log'
Remove-Item -LiteralPath $env:LW_MSIEXEC_LOG -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $env:LW_MANIFEST_DIR -Recurse -Force -ErrorAction SilentlyContinue

$script:failures = 0
function Check([string]$Name, [bool]$Condition) {
    if ($Condition) { Write-Host "  -> [GECTI] $Name" }
    else { Write-Host "  [HATA] $Name"; $script:failures++ }
}

. "$env:LW_REPO_ROOT/bin/legal-workstation.ps1"   # nokta-kaynak: dagitim calismaz

# Sentetik manifest + suite dosyalari.
$uets = Join-Path $env:LW_MANIFEST_DIR 'suite-files/UETS'
$lnk  = Join-Path $env:LW_MANIFEST_DIR 'suite-files/PTT UETS E-Imza.lnk'
New-Item -ItemType Directory -Path $uets -Force | Out-Null
Set-Content -LiteralPath (Join-Path $uets 'uets-eimza.jar') -Value 'x'
Set-Content -LiteralPath $lnk -Value 'x'
Add-LwManifestPath -Path @($uets, $lnk)
Add-LwManifestPackage -ProductCode @('{SUITE-MSI}')

$binDir = Join-Path $env:LW_MANIFEST_DIR 'bin'
New-Item -ItemType Directory -Path $binDir -Force | Out-Null
Set-Content -LiteralPath (Join-Path $binDir 'legal-workstation.ps1') -Value 'x'
$sep = [System.IO.Path]::PathSeparator
$env:Path = "$binDir$sep" + $env:Path

Invoke-Uninstall -AssumeYes

Check "safe: kayitli UETS dizini silindi" (-not (Test-Path -LiteralPath $uets))
Check "safe: kayitli kisayol silindi" (-not (Test-Path -LiteralPath $lnk))
Check "safe: bin dizini silindi" (-not (Test-Path -LiteralPath $binDir))
Check "safe: PATH temizlendi" (($env:Path -split [regex]::Escape($sep)) -notcontains $binDir)
Check "safe: manifest KORUNDU" (Test-Path -LiteralPath (Get-LwManifestPath))
Check "safe: msiexec CAGRILMADI" (-not (Test-Path -LiteralPath $env:LW_MSIEXEC_LOG))

# Review Focus 4: kayitli olmayan dosyaya DOKUNULMAMALI ve zaten silinmis kayitli
# yollarin yeniden temizlenmesi hata vermemelidir (idempotent).
$foreign = Join-Path $env:LW_MANIFEST_DIR 'suite-files/foreign.txt'
Set-Content -LiteralPath $foreign -Value 'x'
Invoke-Uninstall -AssumeYes
Check "safe: kayitli olmayan dosya korunuyor" (Test-Path -LiteralPath $foreign)

# --all: yalnizca kayitli urun kodu kaldirilmali, manifest silinmeli.
Invoke-Uninstall -Complete -AssumeYes
$log = if (Test-Path -LiteralPath $env:LW_MSIEXEC_LOG) { Get-Content -LiteralPath $env:LW_MSIEXEC_LOG -Raw } else { '' }
Check "all: msiexec kayitli kod icin cagrildi" ($log -match '\{SUITE-MSI\}')
Check "all: msiexec /x kullanildi" ($log -match '/x')
Check "all: manifest silindi" (-not (Test-Path -LiteralPath (Get-LwManifestPath)))
Check "all: bin dizini silindi" (-not (Test-Path -LiteralPath (Join-Path $env:LW_MANIFEST_DIR 'bin')))

# Review Focus 2: manifest yok + --all -> dosya temizligi, msiexec YOK.
Remove-Item -LiteralPath $env:LW_MSIEXEC_LOG -Force -ErrorAction SilentlyContinue
Invoke-Uninstall -Complete -AssumeYes
Check "all (manifest yok): msiexec cagrilmadi" (-not (Test-Path -LiteralPath $env:LW_MSIEXEC_LOG))

# Review Focus 5: kayitli urun zaten yoksa (msiexec hata dondurur) temizlik iptal olmamali.
Initialize-LwManifest | Out-Null
Add-LwManifestPackage -ProductCode @('{GONE}')
Invoke-Uninstall -Complete -AssumeYes
Check "all (urun yok): msiexec yine cagrildi" `
    ((Test-Path -LiteralPath $env:LW_MSIEXEC_LOG) -and ((Get-Content -LiteralPath $env:LW_MSIEXEC_LOG -Raw) -match '\{GONE\}'))
Check "all (urun yok): manifest yine de silindi" (-not (Test-Path -LiteralPath (Get-LwManifestPath)))

if ($script:failures -gt 0) { Write-Host "==> [BASARISIZ] $($script:failures) kontrol basarisiz."; exit 1 }
Write-Host "==> [BASARILI] Windows guvenli kaldirma testleri gecti."
exit 0
