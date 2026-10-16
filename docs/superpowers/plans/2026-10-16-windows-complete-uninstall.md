# Windows Complete Uninstall (tracked) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring Windows `uninstall` to parity with Linux — safe mode removes only suite-created
artifacts, and `uninstall --all` removes exactly the MSIs/services/paths the installer newly added,
never touching software the user already had.

**Architecture:** A JSON manifest at `%ProgramData%\legal-workstation\manifest.json` is written
during install by a shared PowerShell library (`lib/manifest.ps1`). MSI installs are recorded by
diffing the Uninstall registry keys before/after, so only newly-added product codes are tracked.
`SCardSvr` state is captured before the installer changes it. At uninstall the CLI reads the
manifest: default `uninstall` is non-destructive (files only); `uninstall --all` additionally
`msiexec /x`-es the recorded product codes and restores the service baseline.

**Tech Stack:** PowerShell 5.1+/pwsh 7 (`ConvertTo-Json`, `Get-CimInstance`, `msiexec`),
`mcr.microsoft.com/powershell` (docker, local), `windows-latest` (CI).

**Spec:** `docs/superpowers/specs/2026-10-16-windows-complete-uninstall-design.md`

---

## Global Constraints

- Single command name: `uninstall`, alias `remove`. Modes: `uninstall`, `uninstall -y`,
  `uninstall --all`, `uninstall --all -y`. Legacy `-Force` == `-y`.
- Never remove an MSI product code that is not in `packages_added`; never revert `SCardSvr` unless
  the manifest records that we changed it.
- Default `uninstall` must **never** call `msiexec` or touch `SCardSvr`.
- Manifest writes are **best-effort**: a failure to record logs a warning, never aborts install.
- All `.ps1` must parse cleanly (`[Parser]::ParseFile`) and must pass on Windows PowerShell 5.1
  semantics (no `$PSVersionTable.Platform` assumptions — treat anything other than `'Unix'` as
  Windows). Files are CRLF per `.gitattributes`.
- Test seams (inert in production): `LW_MANIFEST_DIR`, `LW_MSIEXEC`, `LW_PATH_SCOPE`.
- Tests run on `windows-latest` (CI) and on Linux pwsh via docker (local). No real MSI installs.
- Git author for commits: `Legal Workstation Bot <jesuskane92@gmail.com>`.

## Review Focus

Inputs/conditions the spec implies but no happy-path test covers — each gets a test in its owning
task (listed in that task's steps):

1. **Pre-existing MSI**: user already installed Adalet E-İmza before the suite → its product code
   must not be recorded and `--all` must not remove it. (Task 2, `Get-LwNewProductCodes`.)
2. **No manifest + `--all`**: must degrade to files-only and warn, never call `msiexec`. (Task 5.)
3. **Malformed / partial manifest JSON**: `uninstall` must not crash; treat as empty. (Task 1.)
4. **Recorded path that no longer exists** (or is a file, not a dir): removal must be idempotent and
   not error. (Task 4.)
5. **`--all` where a recorded product is already gone**: `msiexec` failure must not abort the rest
   of cleanup or leave the manifest behind. (Task 5.)

---

### Task 1: Manifest library core + test harness

**Files:**
- Create: `lib/manifest.ps1`
- Create: `tests/windows/manifest.tests.ps1`
- Create: `tests/test-windows-uninstall.sh`

**Interfaces:**
- Produces (consumed by Tasks 2–6):
  - `Get-LwManifestDir` → `string` (env `LW_MANIFEST_DIR`, else `$env:ProgramData\legal-workstation`)
  - `Get-LwManifestPath` → `string`
  - `New-LwManifestDoc` → `[ordered]` hashtable
  - `Read-LwManifest` → `[ordered]` hashtable (missing/malformed → defaults)
  - `Save-LwManifest([System.Collections.IDictionary]$Manifest)` → `void`
  - `Add-LwManifestPackage([string[]]$ProductCode)` → `void`
  - `Add-LwManifestPath([string[]]$Path)` → `void`
  - `Remove-LwManifestFile` → `void` (file, then dir if empty)
  - `Initialize-LwManifest` → `bool`

- [ ] **Step 1: Write the failing test**

`tests/windows/manifest.tests.ps1`:

```powershell
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
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
docker run --rm -v "$PWD:/workspace" -w /workspace \
  -e LW_REPO_ROOT=/workspace -e LW_TEST_ROOT=/tmp/lwtest \
  mcr.microsoft.com/powershell:latest \
  pwsh -NoProfile -Command 'mkdir -Force /tmp/lwtest > $null; & /workspace/tests/windows/manifest.tests.ps1'
```
Expected: FAIL — `. : /workspace/lib/manifest.ps1 ... cannot be found`.

- [ ] **Step 3: Write minimal implementation**

`lib/manifest.ps1`:

```powershell
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
```

`tests/test-windows-uninstall.sh`:

```bash
#!/usr/bin/env bash
# Legal Workstation - Windows kaldirma davranis testleri (pwsh, docker).
set -euo pipefail

DIR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Windows kaldirma davranis testleri baslatiliyor..."

docker run --rm \
    -v "$DIR_ROOT:/workspace" \
    -w /workspace \
    -e LW_REPO_ROOT=/workspace \
    -e LW_TEST_ROOT=/tmp/lwtest \
    mcr.microsoft.com/powershell:latest \
    pwsh -NoProfile -Command '
        New-Item -ItemType Directory -Path $env:LW_TEST_ROOT -Force | Out-Null
        & /workspace/tests/windows/manifest.tests.ps1
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        & /workspace/tests/windows/uninstall.tests.ps1
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    '

echo
echo "==> [BASARILI] Windows kaldirma davranis testleri tamamlandi!"
```

Note: `tests/windows/uninstall.tests.ps1` does not exist until Task 4; create an empty placeholder
now so the wrapper is runnable (**do not** add its tests yet):

```powershell
Write-Host "==> uninstall.tests.ps1 henuz uygulanmadi."
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-windows-uninstall.sh`
Expected: `[BASARILI] Windows manifest testleri gecti.` then the placeholder line, exit 0.

- [ ] **Step 5: Commit**

```bash
git add lib/manifest.ps1 tests/windows/manifest.tests.ps1 tests/windows/uninstall.tests.ps1 tests/test-windows-uninstall.sh
git commit -m "feat(windows): add install manifest library and test harness"
```

---

### Task 2: Registry product-code diff, service baseline, revert plan

**Files:**
- Modify: `lib/manifest.ps1` (append functions)
- Modify: `tests/windows/manifest.tests.ps1` (append cases)

**Interfaces:**
- Consumes: `Read-LwManifest`, `Save-LwManifest` (Task 1).
- Produces (consumed by Tasks 3, 5, 6):
  - `Add-LwManifestService([string]$Unit, [bool]$WasEnabled, [bool]$WasActive, [string]$WasStartMode)` → `void`
  - `Get-LwInstalledProductCodes` → `hashtable` (code → DisplayName)
  - `Get-LwNewProductCodes([IDictionary]$Before, [IDictionary]$After)` → `string[]`
  - `Get-LwServiceBaseline([string]$Name)` → `[ordered]@{ was_enabled; was_active; start_mode }`
  - `Get-LwServiceRevertPlan([IDictionary]$Service)` → `[ordered]@{ SetStartupType; Stop; Start }`
  - `Invoke-LwMsiUninstall([string]$ProductCode)` → `int`

- [ ] **Step 1: Write the failing test**

Append to `tests/windows/manifest.tests.ps1` (before the final `if ($script:failures ...)` block):

```powershell
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-windows-uninstall.sh`
Expected: FAIL — `Add-LwManifestService : The term 'Add-LwManifestService' is not recognized`.

- [ ] **Step 3: Write minimal implementation**

Append to `lib/manifest.ps1`:

```powershell
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-windows-uninstall.sh`
Expected: PASS (all `[GECTI]`), exit 0.

- [ ] **Step 5: Commit**

```bash
git add lib/manifest.ps1 tests/windows/manifest.tests.ps1
git commit -m "feat(windows): record registry product diffs and service baseline"
```

---

### Task 3: CLI manual argument parsing (cross-platform flags)

**Files:**
- Modify: `bin/legal-workstation.ps1:8-16` (replace `param()` block)
- Modify: `bin/legal-workstation.ps1:354-362` (dispatch)
- Create: `tests/windows/cli.tests.ps1`
- Modify: `tests/test-windows-uninstall.sh` (run the new test file)

**Interfaces:**
- Consumes: nothing.
- Produces: `$script:LwCommand`, `$script:LwAll`, `$script:LwYes` populated from `$args`; dispatch
  guarded by `$MyInvocation.InvocationName -ne '.'` so the script can be dot-sourced by tests.

- [ ] **Step 1: Write the failing test**

`tests/windows/cli.tests.ps1`:

```powershell
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
. "$env:LW_CLI_PATH"
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
```

Note: the CLI must be dot-source safe — the validity check and dispatch both live inside the
`$MyInvocation.InvocationName -ne '.'` guard (Step 3), so dot-sourcing never calls `exit`.

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
docker run --rm -v "$PWD:/workspace" -w /workspace -e LW_REPO_ROOT=/workspace -e LW_TEST_ROOT=/tmp/lwtest \
  mcr.microsoft.com/powershell:latest pwsh -NoProfile -Command 'New-Item -ItemType Directory -Path $env:LW_TEST_ROOT -Force > $null; & /workspace/tests/windows/cli.tests.ps1'
```
Expected: FAIL — `--all` is rejected as an unknown parameter (`A parameter cannot be found that matches parameter name 'all'`).

- [ ] **Step 3: Write minimal implementation**

Replace lines 8-16 of `bin/legal-workstation.ps1` (the `[CmdletBinding()] param (...)` block)
with:

```powershell
# PowerShell `--all` / `-y` bayraklarini baglayamaz; Linux ile ayni arayuz icin
# ham $args elle ayristirilir.
$script:LwPositional = @($args | Where-Object { $_ -notlike '-*' })
$script:LwFlags = @($args | Where-Object { $_ -like '-*' } | ForEach-Object { $_.ToLowerInvariant() })
$script:LwCommand = if ($script:LwPositional.Count -gt 0) { $script:LwPositional[0].ToLowerInvariant() } else { 'doctor' }
$script:LwAll = ($script:LwFlags -contains '--all') -or ($script:LwFlags -contains '-all')
$script:LwYes = ($script:LwFlags -contains '-y') -or ($script:LwFlags -contains '--yes') -or
                ($script:LwFlags -contains '-yes') -or ($script:LwFlags -contains '-force') -or
                ($script:LwFlags -contains '--force')

# Bu betik testler tarafindan nokta-kaynak edilebilir; bu durumda komut calistirma.
$script:LwLibFile = Join-Path (Split-Path -Parent $PSScriptRoot) 'lib/manifest.ps1'
if (Test-Path -LiteralPath $script:LwLibFile) { . $script:LwLibFile }
```

Replace the dispatch block (lines 354-362) with:

```powershell
# Bu betik testler tarafindan nokta-kaynak edilebilir; yalnizca normal
# calistirmada komut dogrulanir ve dagitim yapilir.
if ($MyInvocation.InvocationName -ne '.') {
    $valid = @('doctor', 'upgrade', 'update', 'uninstall', 'remove', 'start', 'restart', 'help', '')
    if ($valid -notcontains $script:LwCommand) {
        Write-Failure "Bilinmeyen komut: $script:LwCommand"
        Show-Help
        exit 1
    }
    switch ($script:LwCommand) {
        'doctor'    { Invoke-Doctor }
        'upgrade'   { Invoke-Upgrade }
        'update'    { Invoke-Upgrade }
        'uninstall' { Invoke-Uninstall -Complete:$script:LwAll -AssumeYes:$script:LwYes }
        'remove'    { Invoke-Uninstall -Complete:$script:LwAll -AssumeYes:$script:LwYes }
        'help'      { Show-Help }
        default     { Invoke-Doctor }
    }
}
```

Update `Invoke-Uninstall` signature to accept the new switches (keep it functional; full logic in
Tasks 4–5). For now change its first line to:

```powershell
function Invoke-Uninstall {
    param([switch]$Complete, [switch]$AssumeYes, [switch]$ForceUninstall)
    $ForceUninstall = $ForceUninstall -or $AssumeYes
```

Update `Show-Help` to document the new flags:

```powershell
    Write-Host "  uninstall    Kurulan servisleri, başlatıcıları ve çalışma ortamını sistemden güvenle kaldırır."
    Write-Host "               --all : Kurulumun eklediği MSI/servisleri de kaldırır (tam kaldırma)."
    Write-Host "               -y    : Onay istemeden çalıştırır (--yes / -Force)."
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-windows-uninstall.sh`
Expected: PASS for `cli.tests.ps1`, plus existing manifest tests.

- [ ] **Step 5: Commit**

```bash
git add bin/legal-workstation.ps1 tests/windows/cli.tests.ps1 tests/test-windows-uninstall.sh
git commit -m "feat(windows): parse --all/-y flags for uninstall parity"
```

---

### Task 4: Safe `uninstall` — recorded-only cleanup

**Files:**
- Modify: `bin/legal-workstation.ps1` — rewrite `Invoke-Uninstall` body, add
  `Invoke-LwSafeUninstall`, `Remove-LwMachinePathEntry`, `Get-LwPathScope`
- Replace: `tests/windows/uninstall.tests.ps1` (placeholder → real safe-mode test)
- Create: `tests/windows/msiexec-stub.ps1`

**Interfaces:**
- Consumes: `Read-LwManifest`, `Get-LwManifestDir`, `Get-LwManifestPath` (Task 1).
- Produces (consumed by Task 5):
  - `Invoke-LwSafeUninstall` → `void`
  - `Remove-LwMachinePathEntry([string]$Dir)` → `void`
  - `Get-LwPathScope` → `string`

- [ ] **Step 1: Write the failing test**

`tests/windows/msiexec-stub.ps1`:

```powershell
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest)
if ($env:LW_MSIEXEC_LOG) { Add-Content -LiteralPath $env:LW_MSIEXEC_LOG -Value ($Rest -join ' ') }
if ($Rest -contains '{GONE}') { exit 1605 }   # urun kurulu degil (Review Focus 5)
exit 0
```

`tests/windows/uninstall.tests.ps1`:

```powershell
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

if ($script:failures -gt 0) { Write-Host "==> [BASARISIZ] $($script:failures) kontrol basarisiz."; exit 1 }
Write-Host "==> [BASARILI] Windows guvenli kaldirma testleri gecti."
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-windows-uninstall.sh`
Expected: FAIL — current `Invoke-Uninstall` does not accept `-AssumeYes`/`-Complete`, or the
recorded UETS dir is left in place (`safe: kayitli UETS dizini silindi` HATA).

- [ ] **Step 3: Write minimal implementation**

In `bin/legal-workstation.ps1`, add before `Invoke-Uninstall`:

```powershell
function Get-LwPathScope {
    if ($env:LW_PATH_SCOPE) { return $env:LW_PATH_SCOPE }
    return 'Machine'
}

function Remove-LwMachinePathEntry {
    param([Parameter(Mandatory)][string]$Dir)
    try {
        $scope = Get-LwPathScope
        $path  = [Environment]::GetEnvironmentVariable('Path', $scope)
        if ([string]::IsNullOrEmpty($path)) { return }
        $sep    = [System.IO.Path]::PathSeparator
        $target = $Dir.TrimEnd('\', '/')
        $parts = $path.Split($sep) | Where-Object { $_ -and ($_.TrimEnd('\', '/') -ne $target) }
        $new = ($parts -join $sep)
        if ($new -ne $path) { [Environment]::SetEnvironmentVariable('Path', $new, $scope) }
    } catch { }
}

function Invoke-LwSafeUninstall {
    $installDir = Get-LwManifestDir
    $binDir     = Join-Path $installDir 'bin'
    $libDir     = Join-Path $installDir 'lib'

    Write-Info "Calisan surecler sonlandiriliyor..."
    Get-Process adalet-eimza-tray -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    if (Get-Command Read-LwManifest -ErrorAction SilentlyContinue) {
        $manifest = Read-LwManifest
        foreach ($p in @($manifest.paths)) {
            if ($p -and (Test-Path -LiteralPath $p)) {
                Write-Info "Kayitli dosya kaldiriliyor: $p"
                Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Write-Info "CLI araclari ve PATH temizleniyor..."
    Remove-LwMachinePathEntry -Dir $binDir
    foreach ($d in @($binDir, $libDir)) {
        if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
    }
    # Manifest BILEREK korunur: sonraki 'uninstall --all' hala calisabilsin diye.
}
```

Rewrite `Invoke-Uninstall` body to:

```powershell
function Invoke-Uninstall {
    param([switch]$Complete, [switch]$AssumeYes, [switch]$ForceUninstall)
    $assumeYes = $AssumeYes -or $ForceUninstall

    $hasManifest = (Get-Command Get-LwManifestPath -ErrorAction SilentlyContinue) -and
                   (Test-Path -LiteralPath (Get-LwManifestPath))
    if ($Complete -and -not $hasManifest) {
        Write-Warn "Kurulum manifestosu bulunamadi; '--all' paket/servis kaldirmasi yapamaz. Yalnizca dosyalar temizlenecek."
        $Complete = $false
    }

    if (-not $assumeYes) {
        Write-Host "`nDIKKAT: Bu islem Legal Workstation tarafindan olusturulan dosyalari kaldirir." -ForegroundColor Yellow
        if ($Complete) {
            Write-Host "Sistem paketleri/servisleri de kaldirilacak (--all)." -ForegroundColor Yellow
        }
        $confirm = Read-Host "Kaldirma islemine devam etmek istiyor musunuz? [e/H]"
        if ($confirm -notmatch '^[eEyY]$') { Write-Info "Kaldirma islemi iptal edildi."; return }
        if ($Complete) {
            $token = Read-Host "Tam kaldirmayi onaylamak icin TUMU yazin"
            if ($token -notmatch '^(TUMU|ALL)$') { Write-Info "Tam kaldirma onayi verilmedi. Iptal edildi."; return }
        }
    }

    Write-Step "Legal Workstation (Windows) kaldiriliyor..."
    if ($Complete) { Invoke-LwCompleteUninstall } else { Invoke-LwSafeUninstall }
    Write-Success "Legal Workstation basariyla kaldirildi."
}
```

Add a temporary stub so Task 4 compiles before Task 5 (replaced in Task 5):

```powershell
function Invoke-LwCompleteUninstall {
    Invoke-LwSafeUninstall
    Write-Warn "Tam kaldirma (--all) henuz uygulanmadi."
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-windows-uninstall.sh`
Expected: PASS — all safe-mode checks `[GECTI]`, msiexec never called.

- [ ] **Step 5: Commit**

```bash
git add bin/legal-workstation.ps1 tests/windows/uninstall.tests.ps1 tests/windows/msiexec-stub.ps1
git commit -m "feat(windows): safe uninstall removes only recorded suite artifacts"
```

---

### Task 5: Complete `uninstall --all`

**Files:**
- Modify: `bin/legal-workstation.ps1` — replace the Task 4 stub
  `Invoke-LwCompleteUninstall`, add `Restore-LwService`
- Modify: `tests/windows/uninstall.tests.ps1` (append cases)

**Interfaces:**
- Consumes: `Invoke-LwSafeUninstall`, `Read-LwManifest`, `Invoke-LwMsiUninstall`,
  `Get-LwServiceRevertPlan`, `Remove-LwManifestFile`.
- Produces: `Invoke-LwCompleteUninstall` → `void`; `Restore-LwService([IDictionary]$Service)` → `void`.

- [ ] **Step 1: Write the failing test**

Append to `tests/windows/uninstall.tests.ps1` (before the final summary block):

```powershell
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-windows-uninstall.sh`
Expected: FAIL — `all: msiexec kayitli kod icin cagrildi` HATA (the Task 4 stub never calls msiexec).

- [ ] **Step 3: Write minimal implementation**

Replace the `Invoke-LwCompleteUninstall` stub in `bin/legal-workstation.ps1` with:

```powershell
function Restore-LwService {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Service)
    if ($PSVersionTable.Platform -eq 'Unix') { return }
    $name = [string]$Service.unit
    $plan = Get-LwServiceRevertPlan -Service $Service
    try {
        if ($plan.SetStartupType) {
            Set-Service -Name $name -StartupType $plan.SetStartupType -ErrorAction SilentlyContinue
        }
        if ($plan.Stop) { Stop-Service -Name $name -Force -ErrorAction SilentlyContinue }
        if ($plan.Start) { Start-Service -Name $name -ErrorAction SilentlyContinue }
    } catch { }
}

function Invoke-LwCompleteUninstall {
    $manifest = $null
    if (Get-Command Read-LwManifest -ErrorAction SilentlyContinue) { $manifest = Read-LwManifest }

    Invoke-LwSafeUninstall

    if ($null -ne $manifest) {
        foreach ($code in @($manifest.packages_added)) {
            if (-not $code) { continue }
            Write-Info "MSI kaldiriliyor: $code"
            try {
                $rc = Invoke-LwMsiUninstall -ProductCode $code
                if ($rc -ne 0) { Write-Warn "MSI kaldirma ($code) exit kodu $rc dondurdu." }
            } catch { Write-Warn "MSI kaldirma hatasi ($code): $_" }
        }
        foreach ($svc in @($manifest.services_enabled)) {
            Write-Info "Servis geri aliniyor: $($svc.unit)"
            Restore-LwService -Service $svc
        }
    }

    Remove-LwManifestFile
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-windows-uninstall.sh`
Expected: PASS — complete-mode checks `[GECTI]`, manifest removed, install dir cleaned.

- [ ] **Step 5: Commit**

```bash
git add bin/legal-workstation.ps1 tests/windows/uninstall.tests.ps1
git commit -m "feat(windows): complete uninstall removes recorded MSIs and reverts service"
```

---

### Task 6: `install.ps1` recording wiring + step labels

**Files:**
- Modify: `install.ps1` — dot-source lib, `Initialize-LwManifest`, `Install-SmartCardService`,
  `Install-AkisDriver`, `Install-UyapEditor`, `Install-AdaletEimza`, `Install-Uets`,
  `Setup-CliTools`, `Main`, step labels
- Modify: `tests/test-windows-powershell.sh` — syntax check already covers `install.ps1`

**Interfaces:**
- Consumes: `lib/manifest.ps1` (Tasks 1–2).
- Produces: `Install-LwMsi([string]$MsiPath, [string[]]$ExtraArgs)` → `string[]` (new product codes).

- [ ] **Step 1: Write the failing test**

Add an assertion to `tests/test-windows-powershell.sh` step 1 that `install.ps1` is parse-clean
already happens. Add a **content assertion** verifying recording is wired (grep-style), appended
to the pwsh block after step 1:

```powershell
        Write-Host "==> 1b. install.ps1 kayit entegrasyonu dogrulaniyor..." -ForegroundColor Cyan
        $installText = Get-Content -Raw /workspace/install.ps1
        foreach ($needle in @('Initialize-LwManifest', 'Add-LwManifestService', 'Add-LwManifestPath', 'Install-LwMsi', 'Get-LwManifestDir')) {
            if ($installText -notmatch [regex]::Escape($needle)) {
                Write-Error "install.ps1 eksik: $needle"; exit 1
            }
        }
        Write-Host "  -> [GECTI] install.ps1 gerekli manifest cagrilarini iceriyor." -ForegroundColor Green
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-windows-powershell.sh`
Expected: FAIL — `install.ps1 eksik: Initialize-LwManifest`.

- [ ] **Step 3: Write minimal implementation**

At the top of `install.ps1` (after `[Net.ServicePointManager]...`), add:

```powershell
$script:LwRepoUrl = 'https://raw.githubusercontent.com/AenuHub/linux-legal-workstation/main'
$script:LwLibPath = Join-Path $PSScriptRoot 'lib/manifest.ps1'
if (-not (Test-Path -LiteralPath $script:LwLibPath)) {
    # 'irm | iex' akisinda depo yoktur; kutuphaneyi indir.
    $script:LwLibPath = Join-Path $env:TEMP 'lw-manifest.ps1'
    Invoke-WebRequest -Uri "$script:LwRepoUrl/lib/manifest.ps1" -OutFile $script:LwLibPath -UseBasicParsing
}
. $script:LwLibPath
```

Add `Install-LwMsi` (near the other install functions):

```powershell
function Install-LwMsi {
    param(
        [Parameter(Mandatory)][string]$MsiPath,
        [string[]]$ExtraArgs = @()
    )
    $before = Get-LwInstalledProductCodes
    $argList = @('/i', "`"$MsiPath`"", '/qn', '/norestart') + $ExtraArgs
    Start-Process msiexec.exe -ArgumentList $argList -Wait
    $after = Get-LwInstalledProductCodes
    $new = @(Get-LwNewProductCodes -Before $before -After $after)
    if ($new.Count -gt 0) {
        try { Add-LwManifestPackage -ProductCode $new }
        catch { Write-Warn "Manifestoya MSI kaydi yazilamadi: $_" }
    }
    return $new
}
```

In `Install-SmartCardService`, capture the baseline **before** changing anything:

```powershell
    try {
        $baseline = Get-LwServiceBaseline -Name 'SCardSvr'
        try {
            Add-LwManifestService -Unit 'SCardSvr' -WasEnabled $baseline.was_enabled `
                -WasActive $baseline.was_active -WasStartMode $baseline.start_mode
        } catch { Write-Warn "SCardSvr taban cizgisi kaydedilemedi: $_" }
        if (Get-Command Set-Service -ErrorAction SilentlyContinue) {
            Set-Service -Name SCardSvr -StartupType Automatic -ErrorAction SilentlyContinue
            Start-Service -Name SCardSvr -ErrorAction SilentlyContinue
        }
        Write-Success "Windows Akıllı Kart Servisi (SCardSvr) otomatik başlatmaya ayarlandı ve çalıştırıldı."
    } catch {
        Write-Warn "Akıllı Kart servisi yapılandırılırken uyarı alındı: $_"
    }
```

Replace the four direct MSI installs:
- Temurin: `Install-LwMsi -MsiPath $tmpMsi -ExtraArgs @('ADDLOCAL=FeatureMain,FeatureJavaHome,FeatureJarFileRunWith') | Out-Null`
- AKİA: `Install-LwMsi -MsiPath $msiFile.FullName | Out-Null`
- UKI: `Install-LwMsi -MsiPath $tmpMsi | Out-Null`
- Adalet E-İmza: `Install-LwMsi -MsiPath $tmpMsi | Out-Null`

In `Install-Uets`, record the dir/shortcut when created (full replacement of the `try` block):

```powershell
    try {
        $createdDir = -not (Test-Path -LiteralPath $uetsDir)
        if ($createdDir) {
            New-Item -Path $uetsDir -ItemType Directory -Force | Out-Null
        }

        Write-Info "Resmi PTT UETS sunucusundan uets-eimza.jar indiriliyor..."
        Invoke-WebRequest -Uri $uetsUrl -OutFile $uetsJar -UseBasicParsing
        if ($createdDir) {
            try { Add-LwManifestPath -Path $uetsDir } catch { Write-Warn "UETS dizini kaydedilemedi: $_" }
        }

        if ($PSVersionTable.Platform -ne 'Unix') {
            try {
                $shell = New-Object -ComObject WScript.Shell
                $shortcutPath = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\PTT UETS E-İmza.lnk"
                $shortcut = $shell.CreateShortcut($shortcutPath)

                $javawCmd = Get-Command javaw.exe -ErrorAction SilentlyContinue
                $javawPath = if ($javawCmd) { $javawCmd.Source } else { "javaw.exe" }

                $shortcut.TargetPath = $javawPath
                $shortcut.Arguments = "-jar `"$uetsJar`""
                $shortcut.WorkingDirectory = $uetsDir
                $shortcut.Description = "PTT Ulusal Elektronik Tebligat Sistemi E-İmza Uygulaması"
                $shortcut.Save()
                try { Add-LwManifestPath -Path $shortcutPath } catch { Write-Warn "Kisayol kaydedilemedi: $_" }
            } catch {}
        }

        Write-Success "PTT UETS E-İmza İstemcisi kuruldu ve Başlat Menüsüne eklendi."
    } catch {
        Write-Warn "PTT UETS istemcisi kurulurken uyarı alındı: $_"
    }
```

In `Setup-CliTools`, use the manifest root and ship the library (full replacement):

```powershell
function Setup-CliTools {
    $rootDir    = Get-LwManifestDir
    $installDir = Join-Path $rootDir 'bin'
    $libDir     = Join-Path $rootDir 'lib'
    if (-not (Test-Path $installDir)) { New-Item -Path $installDir -ItemType Directory -Force | Out-Null }
    if (-not (Test-Path $libDir))     { New-Item -Path $libDir -ItemType Directory -Force | Out-Null }

    $repoUrl   = $script:LwRepoUrl
    $scriptDir = $PSScriptRoot

    if ($scriptDir -and (Test-Path "$scriptDir\bin\legal-workstation.ps1")) {
        Copy-Item "$scriptDir\bin\legal-workstation.ps1" -Destination "$installDir\legal-workstation.ps1" -Force
        Copy-Item "$scriptDir\bin\legal-workstation.cmd" -Destination "$installDir\legal-workstation.cmd" -Force
    } else {
        Invoke-WebRequest -Uri "$repoUrl/bin/legal-workstation.ps1" -OutFile "$installDir\legal-workstation.ps1" -UseBasicParsing
        Invoke-WebRequest -Uri "$repoUrl/bin/legal-workstation.cmd" -OutFile "$installDir\legal-workstation.cmd" -UseBasicParsing
    }
    if ($scriptDir -and (Test-Path "$scriptDir\lib\manifest.ps1")) {
        Copy-Item "$scriptDir\lib\manifest.ps1" -Destination "$libDir\manifest.ps1" -Force
    } else {
        Invoke-WebRequest -Uri "$repoUrl/lib/manifest.ps1" -OutFile "$libDir\manifest.ps1" -UseBasicParsing
    }

    # Add to Machine PATH if not present
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    if ($machinePath -notlike "*$installDir*") {
        [Environment]::SetEnvironmentVariable("Path", "$machinePath;$installDir", "Machine")
        $env:Path = "$env:Path;$installDir"
        Write-Success "'legal-workstation' komutu sistem PATH ortamına eklendi."
    }
}
```

In `Main`, initialize the manifest right after `Ensure-Admin`:

```powershell
    if (-not (Initialize-LwManifest)) { Write-Warn "Kurulum manifestosu olusturulamadi; 'uninstall --all' kullanilamayabilir." }
```

and point the final doctor call at the same root:

```powershell
    $cliScript = Join-Path (Get-LwManifestDir) 'bin/legal-workstation.ps1'
```

Fix step labels: `1/5…5/5` → `1/7…5/7` (the `6/7`, `7/7` already correct).

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-windows-powershell.sh`
Expected: PASS (syntax + wiring assertions).

- [ ] **Step 5: Commit**

```bash
git add install.ps1 tests/test-windows-powershell.sh
git commit -m "feat(windows): record installs in the manifest during install"
```

---

### Task 7: Docs (README + CHANGELOG)

**Files:**
- Modify: `README.md` (Windows section)
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Update README**

In the Windows block (near line 43), add an uninstall subsection:

```markdown
**Kaldırma (Windows):**
```powershell
legal-workstation uninstall          # Yalnızca kurulumun oluşturduğu dosyaları kaldırır
legal-workstation uninstall --all    # Kurulumun eklediği MSI/servisleri de kaldırır (tam kaldırma)
```
Kurulumdan önce sisteminizde var olan programlara (ör. kendi kurduğunuz Adalet E-İmza) dokunulmaz.
```

- [ ] **Step 2: Update CHANGELOG**

Add under `## [Unreleased]`:

```markdown
### Added
- Windows `uninstall --all` (tam kaldırma): install-time manifest at
  `%ProgramData%\legal-workstation\manifest.json` records the MSI product codes, suite paths and
  the `SCardSvr` baseline the installer newly added; complete mode removes exactly those.

### Fixed
- Windows `uninstall` no longer removes pre-existing software: MSIs are removed only when the
  manifest records them as newly installed (previously any `Adalet E-İmza` in the registry was
  removed). The `%ProgramFiles%\PTT\UETS` directory and its Start Menu shortcut are removed only
  when recorded as suite-created, and `SCardSvr` is reverted only if the installer changed it.
```

- [ ] **Step 3: Commit**

```bash
git add README.md CHANGELOG.md
git commit -m "docs(windows): document tracked uninstall and complete mode"
```

---

### Task 8: CI wiring

**Files:**
- Modify: `.github/workflows/ci.yml` (extend the `powershell` job)

- [ ] **Step 1: Add CI steps**

In the `powershell` job (after the parse check), add:

```yaml
      - name: Windows manifest tests
        shell: pwsh
        run: |
          $env:LW_REPO_ROOT = $PWD
          $env:LW_TEST_ROOT = Join-Path $env:RUNNER_TEMP 'lwtest'
          New-Item -ItemType Directory -Path $env:LW_TEST_ROOT -Force | Out-Null
          pwsh -NoProfile -File tests/windows/manifest.tests.ps1
          if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
          pwsh -NoProfile -File tests/windows/cli.tests.ps1
          if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
          pwsh -NoProfile -File tests/windows/uninstall.tests.ps1
          if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
```

- [ ] **Step 2: Verify locally**

Run (Linux, docker — the closest local equivalent):
```bash
bash tests/test-windows-uninstall.sh && bash tests/test-windows-powershell.sh
```
Expected: both exit 0.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: run Windows uninstall behavior tests on windows-latest"
```

---

## Verification (after all tasks)

Run:
```bash
bash tests/test-windows-uninstall.sh
bash tests/test-windows-powershell.sh
bash tests/test-manifest.sh
bash tests/test-uninstall-all.sh
```
Expected: all exit 0; no regressions in the Linux suite.

Manual Windows smoke (documented, not automated): on a Windows 10/11 VM, install once, then
`legal-workstation uninstall --all -y` and confirm (a) a pre-installed Adalet E-İmza survives, and
(b) the suite install is gone from "Apps & Features".
