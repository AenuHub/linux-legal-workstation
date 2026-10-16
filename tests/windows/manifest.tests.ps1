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

# Servis taban cizgisi AND-merge (mirror of lib/manifest.py).
Add-LwManifestService -Unit 'SCardSvr' -WasEnabled $false -WasActive $false -WasStartMode 'Manual'
Add-LwManifestService -Unit 'SCardSvr' -WasEnabled $true  -WasActive $true  -WasStartMode 'Automatic'
$svc = (Read-LwManifest).services_enabled | Where-Object { $_.unit -eq 'SCardSvr' }
Check "servis taban cizgisi korunuyor (0/0/Manual)" ((-not $svc.was_enabled) -and (-not $svc.was_active) -and ($svc.was_start_mode -eq 'Manual'))

Add-LwManifestService -Unit 'OtherSvc' -WasEnabled $true -WasActive $true -WasStartMode 'Automatic'
$other = (Read-LwManifest).services_enabled | Where-Object { $_.unit -eq 'OtherSvc' }
Check "onceden acik servis 1/1 korunuyor" ($other.was_enabled -and $other.was_active)

# Zaten kurulu bir urun ASLA yeni sayilmamali (Review Focus 1).
$before = @{ '{OLD}' = 'Adalet E-İmza' }
$after  = @{ '{OLD}' = 'Adalet E-İmza'; '{NEW}' = 'PTT UETS' }
$new = @(Get-LwNewProductCodes -Before $before -After $after)
Check "yalnizca yeni urun kodu kaydedildi" (($new.Count -eq 1) -and ($new[0] -eq '{NEW}'))

# Geri alma plani.
$plan = Get-LwServiceRevertPlan -Service ([ordered]@{ unit = 'SCardSvr'; was_enabled = $false; was_active = $false; was_start_mode = 'Disabled' })
Check "revert plan: start tipi Disabled" ($plan.SetStartupType -eq 'Disabled')
Check "revert plan: durdur" ($plan.Stop -eq $true)
$plan2 = Get-LwServiceRevertPlan -Service ([ordered]@{ unit = 'SCardSvr'; was_enabled = $true; was_active = $true; was_start_mode = 'Automatic' })
Check "revert plan: onceden acik servise dokunma" (($null -eq $plan2.SetStartupType) -and (-not $plan2.Stop))
$plan3 = Get-LwServiceRevertPlan -Service ([ordered]@{ unit = 'SCardSvr'; was_enabled = $false; was_active = $false; was_start_mode = $null })
Check "revert plan: start tipi bilinmiyorsa Manual" ($plan3.SetStartupType -eq 'Manual')

if ($script:failures -gt 0) { Write-Host "==> [BASARISIZ] $($script:failures) kontrol basarisiz."; exit 1 }
Write-Host "==> [BASARILI] Windows manifest testleri gecti."
exit 0
