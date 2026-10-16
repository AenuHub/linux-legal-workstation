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
