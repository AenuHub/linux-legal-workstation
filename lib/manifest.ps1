# Legal Workstation - Windows kurulum manifestosu yardimcilari.
# install.ps1 ve bin/legal-workstation.ps1 tarafindan nokta-kaynak (dot-source) edilir.
# Not: Set-StrictMode kullanilmaz; dot-source edildigi kabugu etkilememesi icin.

function Get-LwManifestDir {
    if ($env:LW_MANIFEST_DIR) { return $env:LW_MANIFEST_DIR }
    if ($env:ProgramData)     { return (Join-Path $env:ProgramData 'legal-workstation') }
    return (Join-Path ([System.IO.Path]::GetTempPath()) 'legal-workstation')
}

function Get-LwManifestPath { Join-Path (Get-LwManifestDir) 'manifest.json' }

function New-LwManifestDoc {
    [ordered]@{
        manifest_version = 1
        installed_at     = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        os_family        = 'windows'
        packages_added   = @()
        services_enabled = @()
        paths            = @()
        rc_files         = @()
    }
}

function Read-LwManifest {
    $doc  = New-LwManifestDoc
    $path = Get-LwManifestPath
    if (Test-Path -LiteralPath $path) {
        try {
            $obj = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -ne $obj) {
                if ($obj.manifest_version) { $doc.manifest_version = [int]$obj.manifest_version }
                if ($obj.installed_at)     { $doc.installed_at = [string]$obj.installed_at }
                if ($obj.os_family)        { $doc.os_family = [string]$obj.os_family }
                foreach ($key in 'packages_added', 'paths', 'rc_files') {
                    if ($obj.PSObject.Properties.Name -contains $key) {
                        $doc[$key] = @($obj.$key | ForEach-Object { [string]$_ })
                    }
                }
                if ($obj.PSObject.Properties.Name -contains 'services_enabled') {
                    $doc.services_enabled = @($obj.services_enabled | ForEach-Object {
                        $mode = $null
                        if ($_.PSObject.Properties.Name -contains 'was_start_mode') { $mode = [string]$_.was_start_mode }
                        [ordered]@{
                            unit           = [string]$_.unit
                            was_enabled    = [bool]$_.was_enabled
                            was_active     = [bool]$_.was_active
                            was_start_mode = $mode
                        }
                    })
                }
            }
        } catch { }
    }
    return $doc
}

function Save-LwManifest {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Manifest)
    $dir = Get-LwManifestDir
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    foreach ($key in 'packages_added', 'paths', 'rc_files') {
        $Manifest[$key] = @($Manifest[$key])
    }
    $target = Get-LwManifestPath
    $tmp    = "$target.tmp"
    $json   = $Manifest | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($tmp, $json + "`n", (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination $target -Force
}

function Add-LwManifestPackage {
    param([Parameter(Mandatory)][string[]]$ProductCode)
    $doc = Read-LwManifest
    foreach ($code in $ProductCode) {
        if ($code -and ($doc.packages_added -notcontains $code)) { $doc.packages_added += $code }
    }
    Save-LwManifest $doc
}

function Add-LwManifestPath {
    param([Parameter(Mandatory)][string[]]$Path)
    $doc = Read-LwManifest
    foreach ($item in $Path) {
        if ($item -and ($doc.paths -notcontains $item)) { $doc.paths += $item }
    }
    Save-LwManifest $doc
}

# Bir yolu yalnizca BIZ olusturduysak kaydeder. Onceden var olan bir dosya/
# dizin (or. kullanicinin kendi PTT UETS kisayolu) asla sahiplenilmez; boylece
# 'uninstall' onu silmez. Kaydettiyse $true, atladiysa $false dondurur.
function Add-LwManifestCreatedPath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [bool]$Existed
    )
    if ($Existed) { return $false }
    Add-LwManifestPath -Path $Path
    return $true
}

function Remove-LwManifestFile {
    $path = Get-LwManifestPath
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
    $dir = Get-LwManifestDir
    if ((Test-Path -LiteralPath $dir) -and
        -not (Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue)) {
        Remove-Item -LiteralPath $dir -Force -ErrorAction SilentlyContinue
    }
}

function Initialize-LwManifest {
    try { Save-LwManifest (Read-LwManifest); return $true }
    catch { return $false }
}

function Add-LwManifestService {
    param(
        [Parameter(Mandatory)][string]$Unit,
        [bool]$WasEnabled,
        [bool]$WasActive,
        [string]$WasStartMode
    )
    $doc  = Read-LwManifest
    $prev = $doc.services_enabled | Where-Object { $_.unit -eq $Unit } | Select-Object -First 1
    $enabled = $WasEnabled; $active = $WasActive; $mode = $WasStartMode
    if ($null -ne $prev) {
        # AND-merge: ikinci kurulum servisi zaten acik gorse bile taban cizgisi korunur.
        $enabled = ([bool]$prev.was_enabled) -and $enabled
        $active  = ([bool]$prev.was_active)  -and $active
        if ($prev.was_start_mode) { $mode = [string]$prev.was_start_mode }
    }
    $doc.services_enabled = @($doc.services_enabled | Where-Object { $_.unit -ne $Unit })
    $doc.services_enabled += [ordered]@{
        unit = $Unit; was_enabled = $enabled; was_active = $active; was_start_mode = $mode
    }
    Save-LwManifest $doc
}

function Get-LwInstalledProductCodes {
    # Test seam: bu ortam degiskeni ayarliysa urun kodlari kayit defteri yerine
    # dosyadan okunur (CI'da gercek registry/msiexec olmadan kayit mantigini test
    # etmek icin). Uretimde tanimsizdir.
    if ($env:LW_REG_KEYS_FILE) {
        $fromFile = @{}
        if (Test-Path -LiteralPath $env:LW_REG_KEYS_FILE) {
            foreach ($line in (Get-Content -LiteralPath $env:LW_REG_KEYS_FILE)) {
                if ($line -and $line.Trim()) { $fromFile[$line.Trim()] = '' }
            }
        }
        return $fromFile
    }
    $result = @{}
    $roots  = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        Get-ChildItem $root -ErrorAction SilentlyContinue | ForEach-Object {
            $code = $_.PSChildName
            $name = ''
            try { $name = [string](Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).DisplayName } catch { }
            $result[$code] = $name
        }
    }
    return $result
}

function Get-LwNewProductCodes {
    param(
        [System.Collections.IDictionary]$Before,
        [System.Collections.IDictionary]$After
    )
    $new = @()
    foreach ($code in $After.Keys) {
        if (-not $Before.Contains($code)) { $new += $code }
    }
    return $new
}

function Get-LwServiceBaseline {
    param([Parameter(Mandatory)][string]$Name)
    $result = [ordered]@{ was_enabled = $false; was_active = $false; start_mode = $null }
    try {
        $svc = Get-CimInstance -ClassName Win32_Service -Filter "Name='$Name'" -ErrorAction Stop
        if ($null -ne $svc) {
            $mode = switch ($svc.StartMode) {
                'Auto'     { 'Automatic' }
                'Manual'   { 'Manual' }
                'Disabled' { 'Disabled' }
                default    { $null }
            }
            $result.start_mode  = $mode
            $result.was_enabled = ($mode -eq 'Automatic')
            $result.was_active  = ($svc.State -eq 'Running')
        }
    } catch { }
    return $result
}

function Get-LwServiceRevertPlan {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Service)
    $startup = $null
    if (-not [bool]$Service.was_enabled) {
        $startup = if ($Service.was_start_mode) { [string]$Service.was_start_mode } else { 'Manual' }
    }
    return [ordered]@{
        SetStartupType = $startup
        Stop           = (-not [bool]$Service.was_active)
        Start          = ([bool]$Service.was_active)
    }
}

function Invoke-LwMsiUninstall {
    param([Parameter(Mandatory)][string]$ProductCode)
    $exe = if ($env:LW_MSIEXEC) { $env:LW_MSIEXEC } else { 'msiexec.exe' }
    & $exe '/x' $ProductCode '/qn' '/norestart'
    $code = $LASTEXITCODE
    if ($null -eq $code) { $code = if ($?) { 0 } else { 1 } }
    return [int]$code
}

# Bir MSI kurar ve yalnizca YENI eklenen urun kodlarini manifestoya kaydeder.
# Kurulumdan ONCE var olan urunler (ornegin kullanicinin onceden kurdugu Adalet
# E-Imza) hicbir zaman kaydedilmez; bu yuzden 'uninstall --all' onlara dokunmaz.
function Install-LwMsi {
    param(
        [Parameter(Mandatory)][string]$MsiPath,
        [string[]]$ExtraArgs = @()
    )
    $before = Get-LwInstalledProductCodes
    $exe = if ($env:LW_MSIEXEC) { $env:LW_MSIEXEC } else { 'msiexec.exe' }
    if ($env:LW_MSIEXEC) {
        # Test seam: Start-Process bir .ps1 stub'ini calistiramaz.
        $callArgs = @('/i', $MsiPath, '/qn', '/norestart') + $ExtraArgs
        & $exe @callArgs | Out-Null
    } else {
        $argList = @('/i', "`"$MsiPath`"", '/qn', '/norestart') + $ExtraArgs
        Start-Process $exe -ArgumentList $argList -Wait
    }
    $after = Get-LwInstalledProductCodes
    $new = @(Get-LwNewProductCodes -Before $before -After $after)
    if ($new.Count -gt 0) {
        try { Add-LwManifestPackage -ProductCode $new }
        catch { Write-Warning "MSI kaydi manifestoya yazilamadi: $_" }
    }
    return $new
}
