# Windows Complete Uninstall (tracked) — Design

- **Date:** 2026-10-16
- **Status:** Approved (phase 2 of the uninstall work)
- **Branch:** `feat/windows-complete-uninstall`
- **Scope:** Windows 10/11 only. macOS remains phase 3.
- **Supersedes the phase-2 note** in `2026-10-16-complete-uninstall-design.md` §11.

## 1. Problem

The Windows CLI (`bin/legal-workstation.ps1`) ships an `uninstall` that is **not** safe and cannot
be complete:

| # | Severity | Location | Problem |
|---|---|---|---|
| WP1 | Critical | `bin/legal-workstation.ps1` `Invoke-Uninstall` | Scans the registry for any `DisplayName -like '*Adalet E-İmza*'` and runs `msiexec /x`, deleting the user's **pre-existing** Adalet E-İmza. Violates the documented "önceden kurulu programlara dokunulmaz" promise. |
| WP2 | Critical | whole Windows path | **No manifest.** Nothing records what the installer added, so `uninstall --all` is impossible and even safe mode can't tell "ours" from "theirs". |
| WP3 | Important | `install.ps1` `Install-SmartCardService` | `SCardSvr` is forced to Automatic + started with no capture of prior state; uninstall never reverts it. |
| WP4 | Important | `bin/legal-workstation.ps1` | `%ProgramFiles%\PTT\UETS` deleted unconditionally if present — could wipe a pre-existing UETS install. |
| WP5 | Important | `install.ps1` MSI steps | Temurin JRE / AKİA / UKI / Adalet E-İmza product codes are never captured; a "complete" uninstall has nothing to target. |
| WP6 | Minor | `install.ps1` | Step labels `1/5…5/5` then `6/7`, `7/7` — inconsistent (7 steps). |
| WP7 | Minor | CLI surface | Only `uninstall [-Force]`; no `--all` / `-y` parity with Linux. |
| WP8 | Minor | CLI | The Start Menu `.lnk` is removed only *inside* the `Test-Path $uetsDir` guard, so a leftover shortcut is never cleaned when the dir is gone. |

## 2. Goals

- Same contract as Linux: safe `uninstall` removes only suite-created artifacts; `uninstall --all`
  removes **exactly** what the installer newly added.
- Never remove a pre-existing MSI/app/driver, even if it matches a known name.
- Never revert `SCardSvr` unless the installer changed it.
- Keep one command name (`uninstall`, alias `remove`) with modes `uninstall`, `-y`, `--all`,
  `--all -y`.

## 3. Non-goals

- macOS (phase 3), user certificates/keys, per-user manifests.
- Tracking MSI *upgrades*; only newly-installed products are recorded.
- Removing Java/AKİA/UYAP if the user had them before install.

## 4. Manifest

- **Location:** `%ProgramData%\legal-workstation\manifest.json` (machine-wide, because install is
  elevated and all MSIs are machine-scoped). Overridable for tests/CI via `LW_MANIFEST_DIR`.
- **Schema:** identical to Linux (`manifest_version`, `installed_at`, `os_family`, `packages_added`,
  `services_enabled`, `paths`, `rc_files`), with `os_family: "windows"`.
- Windows mappings:
  - `packages_added` → **MSI product-code GUIDs** (DisplayName resolved from the registry at
    uninstall time; no schema change).
  - `services_enabled` → `{unit, was_enabled, was_active, was_start_mode}` where `was_start_mode`
    is an **additive** key (`Automatic`/`Manual`/`Disabled`) so we can restore the exact prior
    start type — a bool cannot express three states.
  - `paths` → suite-created dirs/files (UETS dir, Start Menu `.lnk`, CLI dir).
  - `rc_files` → unused on Windows (PATH is a registry value); the machine PATH entry is
    unambiguously ours (`%ProgramData%\legal-workstation\bin`) and handled directly.
- Written atomically (temp file + `Move-Item -Force`).

## 5. Install-time recording

A shared library `lib/manifest.ps1` is dot-sourced by **both** `install.ps1` and the CLI, and copied
into `%ProgramData%\legal-workstation\lib\manifest.ps1` by `Setup-CliTools` (mirrors Linux shipping
`lib/common.sh`/`lib/manifest.py`).

- `Initialize-LwManifest` runs right after elevation, before any component install; best-effort
  (a write failure warns, never aborts).
- **MSI recording:** before each `msiexec /i`, snapshot the Uninstall registry keys
  (`HKLM`, `HKLM\WOW6432Node`, `HKCU`); after install, snapshot again; **diff → record only the new
  product code(s)**. A pre-existing product produces no new key, so it is never recorded → WP1/WP5.
- **Service baseline:** capture `SCardSvr` start mode + running state *before* changing, then
  `Add-LwManifestService`; only then set Automatic + start.
- **Paths:** record the UETS dir only if *we* created it; record the Start Menu `.lnk` when created;
  the CLI dir/PATH entry are derived from our own name and need no manifest (WP4/WP8).

## 6. Safe `uninstall` (default)

1. Stop the suite `adalet-eimza-tray` process.
2. Remove only **recorded** `paths` (UETS dir, shortcut, …). Unrecorded → untouched.
3. Remove our own CLI `bin`/`lib` dirs + the machine PATH entry (always provably ours).
4. **Keep `manifest.json`** so a later `--all` still works (mirrors the intentional Linux behavior).
5. Never run `msiexec /x`; never alter `SCardSvr`.

## 7. `uninstall --all`

Safe cleanup, then:

1. `msiexec /x <product-code> /qn /norestart` for each **recorded** product code
   (`LW_MSIEXEC` overridable for tests). Failures are reported, not fatal.
2. Restore `SCardSvr`: set the recorded start mode if we changed it; stop only if we started it
   (was not active before).
3. Remove any remaining recorded paths.
4. Delete the manifest **last**.

No manifest → `--all` refuses MSI/service removal, performs files-only cleanup, and prints why.

## 8. CLI surface

- `uninstall` / `remove`; flags `-All`/`--all`, `-Yes`/`-y`/`--yes`; legacy `-Force` maps to `-Yes`.
- PowerShell cannot bind `--all`; the CLI parses raw `$args` manually for cross-platform parity.
- Interactive `--all` requires typing `TUMU` (accepts `ALL`) after the `[e/H]` prompt; `-y` skips both.
- The `.cmd` wrapper passes args through unchanged.

## 9. Safety rules

- A product code is removed only if in `packages_added`.
- A recorded path is removed only if present in `paths`; the CLI's own dir is the sole exception.
- `SCardSvr` is reverted only from recorded state.
- `--all` always requires explicit confirmation.

## 10. Testing

Container/host-agnostic pwsh tests run on both Linux pwsh (docker, local) and `windows-latest` CI:

- `tests/windows/manifest.tests.ps1` — init, round-trip, dedup, service AND-merge, product-code
  diff, revert-plan, malformed-JSON recovery, delete.
- `tests/windows/uninstall.tests.ps1` — end-to-end via the real CLI functions with a temp
  `LW_MANIFEST_DIR`, `LW_PATH_SCOPE=Process`, and a pwsh msiexec stub: safe mode removes only
  recorded paths and **never** calls msiexec; `--all` calls msiexec for recorded codes only,
  deletes the manifest, and strips PATH; missing-manifest `--all` degrades to files-only.
- `tests/test-windows-uninstall.sh` — docker wrapper for local runs (mirrors
  `test-windows-powershell.sh`).
- `.github/workflows/ci.yml` — the `powershell` job runs both test files natively on
  `windows-latest`.

## 11. Test seams (deliberate, minimal)

- `LW_MANIFEST_DIR` — manifest + CLI install-dir root. Inert in production.
- `LW_MSIEXEC` — command used for MSI removal (default `msiexec.exe`).
- `LW_PATH_SCOPE` — environment scope for PATH edits (default `Machine`; tests use `Process`).

## 12. Files touched

- `lib/manifest.ps1` (new) — manifest + registry-diff + service helpers.
- `bin/legal-workstation.ps1` — manual arg parsing, safe/complete uninstall, help.
- `install.ps1` — dot-source lib, initialize manifest, MSI diff-recording, `SCardSvr` baseline,
  UETS/shortcut recording, copy `lib/manifest.ps1`, fix step labels.
- `tests/windows/*` (new), `tests/test-windows-uninstall.sh` (new).
- `.github/workflows/ci.yml`, `README.md`, `CHANGELOG.md`.
