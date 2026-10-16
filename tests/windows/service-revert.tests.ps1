$ErrorActionPreference = 'Stop'

. "$env:LW_REPO_ROOT/lib/manifest.ps1"
. "$env:LW_REPO_ROOT/bin/legal-workstation.ps1"

$script:failures = 0
function Check([string]$Name, [bool]$Condition) {
    if ($Condition) { Write-Host "  -> [GECTI] $Name" }
    else { Write-Host "  [HATA] $Name"; $script:failures++ }
}

# Servis geri alma cagrilarini gercekten calistirmadan dogrulamak icin kayit seam'i.
$log = Join-Path $env:LW_TEST_ROOT 'svc.log'
$env:LW_SERVICE_LOG = $log

# 1) Kurulumdan ONCE kapali + pasif olan servis: --all sonrasi Manual'e donmeli ve
#    durdurulmus olmali, asla baslatilmamali.
Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
$off = [ordered]@{ unit = 'SCardSvr'; was_enabled = $false; was_active = $false; was_start_mode = 'Manual' }
Restore-LwService -Service $off
$lines = @(Get-Content -LiteralPath $log -ErrorAction SilentlyContinue)
Check "kapali servis: Manual baslangic turune ayarlandi" ($lines -contains 'SetStartupType SCardSvr Manual')
Check "kapali servis: durduruldu" ($lines -contains 'Stop SCardSvr')
Check "kapali servis: baslatilmadi" (-not ($lines -contains 'Start SCardSvr'))

# 2) Kurulumdan ONCE acik + aktif olan servis: baslangic turu degistirilmemeli ve
#    durdurulmamali; calisma durumu (aktif) korunur.
Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
$on = [ordered]@{ unit = 'SCardSvr'; was_enabled = $true; was_active = $true; was_start_mode = 'Automatic' }
Restore-LwService -Service $on
$lines2 = @(Get-Content -LiteralPath $log -ErrorAction SilentlyContinue)
Check "acik servis: baslangic turu degistirilmedi" (@($lines2 | Where-Object { $_ -like 'SetStartupType*' }).Count -eq 0)
Check "acik servis: durdurulmadi" (-not ($lines2 -contains 'Stop SCardSvr'))
Check "acik servis: aktif durum korunur (Start)" ($lines2 -contains 'Start SCardSvr')

# 3) Kayitli birim adi yoksa hicbir sey yapilmamali.
Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
$anon = [ordered]@{ was_enabled = $false; was_active = $false }
Restore-LwService -Service $anon
$lines3 = @(Get-Content -LiteralPath $log -ErrorAction SilentlyContinue)
Check "birim adi yok: hicbir islem yapilmadi" ($lines3.Count -eq 0)

if ($script:failures -gt 0) { Write-Host "==> [BASARISIZ] $($script:failures) kontrol basarisiz."; exit 1 }
Write-Host "==> [BASARILI] Windows servis geri alma testleri gecti."
exit 0
