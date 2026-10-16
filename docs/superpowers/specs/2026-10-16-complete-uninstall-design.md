# Legal Workstation — Complete Uninstall (tracked) — Design

- **Date:** 2026-10-16
- **Status:** Draft — awaiting review
- **Branch:** `feat/complete-uninstall`
- **Scope of this phase:** Linux (Arch, Debian/Ubuntu, Fedora). Schema designed cross-platform;
  Windows/macOS implementation is phase 2.

## 1. Problem

`legal-workstation uninstall` removes only part of what the installer creates:

| Leftover today | Created by |
|---|---|
| `akia.desktop` (user + `/usr/share/applications`) | `common_ensure_akia_desktop` |
| `export PATH=...` line in `~/.bashrc/.zshrc/.profile` | `ensure_local_bin_on_path` |
| `/opt/Akia`, `/usr/local/bin/akia`, `/usr/lib/libakisp11.so` | AKİA install |
| `/usr/share/java/uyap-editor/*` (and Debian's dpkg-managed UKI package) | UYAP editor install |
| stray `~/.local/share/icons/*` from the e-imza deb | e-imza install |
| **system packages** (`pcsclite`, `ccid`, `opensc`, `pcsc-tools`, `jre11-openjdk`, `libayatana-appindicator3`, …) | `*_install_system_packages` |
| `pcscd` service left enabled/started | `*_install_system_packages` |

There is no way for a user to fully undo an installation: system packages and the smart-card
service remain. A "complete uninstall" must remove those **without** touching software the user
already had before installing Legal Workstation.

## 2. Goals

- Keep a **single command**, `uninstall`, to avoid confusing users. No new command name.
- Default behaviour stays **safe**: remove only suite-created artifacts, never packages.
- Add a **complete mode** (`uninstall --all`) that removes exactly the system packages and
  services the installer *newly added*, using an install-time manifest.
- Never remove a package that was present before installation.
- Design the manifest schema cross-platform; implement Linux now, Windows/macOS in phase 2.

## 3. Non-goals

- Removing user documents, certificates, or keys.
- Removing packages the user had before install.
- Implementing Windows/macOS complete-uninstall in this phase (stub + documented mapping only).
- A separate `purge` command (rejected: confuses users).

## 4. Command surface

| Invocation | Behaviour |
|---|---|
| `legal-workstation uninstall` | Safe cleanup; interactive `[e/H]` prompt. |
| `legal-workstation uninstall -y` / `--yes` | Safe cleanup, no prompt. |
| `legal-workstation uninstall --all` | Safe cleanup **+** revert services **+** remove tracked packages; strong confirmation. |
| `legal-workstation uninstall --all -y` | Complete cleanup, no prompt. |
| `legal-workstation remove ...` | Alias of `uninstall` (unchanged). |

Interactive `--all` requires typing `TUMU` (accepted: `ALL`) after the initial `[e/H]` prompt,
because it removes system packages. `-y` skips both prompts.

## 5. Manifest

- **Location:** `${XDG_DATA_HOME:-$HOME/.local/share}/legal-workstation/manifest.json`
- **Owner:** the installing user. `--all` reads it and uses `sudo` only for system removals.
- **Written with:** `python3` (already a dependency) for robust JSON; written atomically
  (temp file + `mv`).

Schema (`manifest_version: 1`):

```json
{
  "manifest_version": 1,
  "installed_at": "2026-10-16T12:00:00Z",
  "os_family": "arch",
  "packages_added": ["ccid", "opensc", "pcsc-tools", "jre11-openjdk", "libayatana-appindicator3"],
  "services_enabled": [
    {"unit": "pcscd.socket", "was_enabled": false, "was_active": false}
  ],
  "paths": ["/opt/uets", "/usr/local/bin/uets-eimza", "/opt/Akia", "/usr/share/java/uyap-editor"],
  "rc_files": ["/home/ali/.bashrc", "/home/ali/.zshrc"],
  "cli_path": "/home/ali/.local/bin/legal-workstation"
}
```

`packages_added` is the authoritative list of packages `--all` may remove. Paths and `rc_files`
drive the file/`PATH` cleanup.

## 6. Install-time recording

New helpers in `lib/common.sh`:

- `manifest_path` — resolve the manifest location.
- `manifest_init` — create/merge the manifest for the current `os_family` (idempotent).
- `manifest_record_package <pkg>` — append if absent.
- `manifest_record_service <unit> <was_enabled> <was_active>`.
- `manifest_record_path <path>`.
- `manifest_record_rc <file>`.
- `manifest_save` — atomic write.

In each `*_install_system_packages`:

- Before installing, test each candidate with the distro tool
  (`pacman -Qq "$pkg"`, `dpkg-query -W -f='${Status}'`, `rpm -q "$pkg"`).
  Only packages **not already present** are recorded via `manifest_record_package`.
- Before `systemctl enable --now`, capture `was_enabled` / `was_active` and record the service.

Recording is **best-effort**: a failure to write the manifest must never abort an install
(wrap in `|| log_warn`), but is reported so the user knows `--all` may be unavailable later.

## 7. Enhanced safe `uninstall` (default mode)

Keeps its non-destructive contract and additionally removes the leftovers in §1 that are
suite-scoped and safe: `akia.desktop` (user + system), the `legal-workstation` marker lines,
`/usr/local/bin/akia`, `/usr/lib/libakisp11.so`, `/usr/share/java/uyap-editor`, stray e-imza
icons. It still never removes packages or system services.

## 8. Complete mode (`uninstall --all`) sequence

1. Run the enhanced safe `uninstall` (files, desktop entries, user service, CLI).
2. **Revert services:** for each recorded service, `disable`/`stop` **only if**
   `was_enabled`/`was_active` were false (i.e. we enabled it).
3. **Remove packages:** reinstall-free removal of exactly `packages_added`:
   - Arch: `sudo pacman -Rs --noconfirm <pkgs>`
   - Debian: `sudo apt-get remove -y <pkgs> && sudo apt-get autoremove -y`
   - Fedora: `sudo dnf remove -y <pkgs>`
   Removal failures are reported, not fatal to the rest of the cleanup.
4. **Remove remaining system paths** from the manifest and the known AKİA/UYAP locations.
5. **Strip rc lines:** remove the `# Added by legal-workstation` marker and the following
   `export PATH=...` line from each recorded rc file.
6. **Delete the manifest and state dir.**

## 9. Safety rules

- No manifest → `--all` refuses package/service removal and performs files-only cleanup,
  printing why.
- A package not in `packages_added` is never removed, even if it matches a known name.
- A service is only reverted if we enabled/started it.
- `--all` always requires explicit confirmation (`TUMU` or `-y`).

## 10. Upgrade integration

`legal-workstation upgrade` re-runs install steps, which call `manifest_init` in merge mode:
existing entries are preserved, newly added packages/services are appended (no duplicates).

## 11. Cross-platform posture

Manifest schema, `os_family` values, and helper names are platform-agnostic. Phase 1 adds
Linux recording + `--all`. On Windows/macOS, `uninstall --all` prints
"complete mode not yet available on this platform — running safe uninstall" and performs the
safe path. The spec records the phase-2 mapping (Windows: MSI product codes/registry; macOS:
`/Applications` bundles, `/opt/uets`, `.pkg` receipts) for the follow-up plan.

## 12. Testing (TDD)

No root, no real package manager: put **fake `pacman` / `dpkg-query` / `rpm` shims**
and a fake `systemctl` on `PATH`, and drive the flow with a temporary `HOME`.

Tests:

- `tests/test-manifest.sh` — init, record, merge-idempotency, atomic save, malformed-JSON recovery.
- `tests/test-uninstall-safe.sh` — safe mode removes the new leftovers and the rc marker, and
  leaves packages untouched.
- `tests/test-uninstall-all.sh` — with a synthetic manifest, `--all` targets **only** recorded
  packages, reverts only services we enabled, strips rc lines, and deletes the manifest;
  missing-manifest fallback refuses package removal.

All tests wired into `.github/workflows/ci.yml`.

## 13. Files touched

- `lib/common.sh` — manifest helpers + `uninstall_purge` orchestration.
- `lib/{arch,debian,fedora}.sh` — presence checks + recording + enhanced file cleanup lists.
- `bin/legal-workstation` — `uninstall` argument parsing (`--all`, `-y`/`--yes`), safe vs complete.
- `install.sh` — `manifest_init` at start; `ensure_local_bin_on_path` records rc files.
- `README.md`, `CHANGELOG.md` — document `uninstall` vs `uninstall --all`.
- `tests/*`, `.github/workflows/ci.yml`.

## 14. Open questions

- None blocking. Confirmation token defaults to `TUMU` (accepts `ALL`).
