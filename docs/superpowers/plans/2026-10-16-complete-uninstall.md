# Complete Uninstall (tracked) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `legal-workstation uninstall` fully undo an installation — safely removing the
suite's files/services today, and (with `--all`) exactly the system packages/services the
installer newly added — without ever touching software the user had before.

**Architecture:** A small JSON manifest at
`${XDG_DATA_HOME:-$HOME/.local/share}/legal-workstation/manifest.json` is written during install
by a helper (`lib/manifest.py`, wrapped by bash functions in `lib/common.sh`). Each distro engine
records only the packages it actually adds (presence check first) and the service state *before*
enabling `pcscd`. At uninstall time the existing CLI reads the manifest: default `uninstall` stays
non-destructive (files only, now more complete); `uninstall --all` additionally reverts the
recorded services and removes only the recorded packages.

**Tech Stack:** Bash 4+, `python3` (already a dependency for JSON handling), the distro package
managers (`pacman`/`apt-get`/`dnf`), `systemctl`, GitHub Actions.

**Design spec:** `docs/superpowers/specs/2026-10-16-complete-uninstall-design.md`.

---

## Global Constraints

- Single command name — **no new top-level command**. Everything hangs off `uninstall`
  (`remove` stays an alias). Modes: `uninstall`, `uninstall -y`, `uninstall --all`,
  `uninstall --all -y`.
- Never remove a package that is not in `packages_added`; never revert a service that was already
  enabled/active before install.
- Default `uninstall` must **never** touch system packages or `pcscd`.
- Manifest writes are **best-effort**: a failure to record must log a warning, never abort install.
- Recording must be a no-op-safe under `LW_DRY_RUN=1`.
- All new/changed shell must pass `bash -n` and `shellcheck --severity=error`; tests run on
  `ubuntu-latest` CI with **no root**, using fake `sudo`/`systemctl`/package-manager shims.
- Test scripts follow the existing convention: `tests/test-*.sh`, `set -euo pipefail`, a
  `pass`/`fail` helper, non-zero exit on any failure, Turkish messages.
- Git author for commits: `Legal Workstation Bot <jesuskane92@gmail.com>`.

**Test seam:** add an `LW_OS_OVERRIDE` hook to `detect_os` so tests can pin the detected distro
without a container. It is inert in production (unset).

---

## File Structure

| File | Responsibility |
|---|---|
| `lib/manifest.py` **(new)** | Read/write the JSON manifest; subcommands only, no policy. |
| `lib/common.sh` **(modify)** | Bash wrappers (`manifest_*`), `pkg_present`, `remove_local_bin_from_path`, `LW_OS_OVERRIDE` seam, record rc files. |
| `lib/arch.sh`, `lib/debian.sh`, `lib/fedora.sh` **(modify)** | One recording call per system-package step + service-state capture. |
| `bin/legal-workstation` **(modify)** | `cmd_uninstall`: argument parsing, enhanced safe cleanup, `uninstall_complete` for `--all`. |
| `install.sh` **(modify)** | `manifest_init`; install `lib/common.sh` + `lib/manifest.py` to `~/.local/lib`. |
| `tests/test-manifest.sh` **(new)** | Manifest store + wrappers. |
| `tests/test-uninstall-safe.sh` **(new)** | Default uninstall completeness + "packages untouched". |
| `tests/test-uninstall-all.sh` **(new)** | `--all` targets only recorded packages/services; missing-manifest fallback. |
| `.github/workflows/ci.yml` **(modify)** | Run the three new tests. |
| `README.md`, `CHANGELOG.md` **(modify)** | Document `uninstall` vs `uninstall --all`. |

---

## Task 1: Manifest store + bash wrappers

**Files:**
- Create: `lib/manifest.py`
- Modify: `lib/common.sh` (append helpers; add `LW_OS_OVERRIDE` to `detect_os`)
- Test: `tests/test-manifest.sh`

- [ ] **Step 1: Write the failing test** `tests/test-manifest.sh`

```bash
#!/usr/bin/env bash
# Legal Workstation - kurulum manifestosu (install-time tracking) testi
set -euo pipefail

DIR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failures=0
pass() { printf '  -> [GECTI] %s\n' "$1"; }
fail() { printf '  [HATA] %s\n' "$1"; failures=$((failures + 1)); }

echo "==> Kurulum manifestosu test ediliyor..."
tmp_home="$(mktemp -d /tmp/lw-manifest-XXXXXX)"
trap 'rm -rf "$tmp_home"' EXIT
export HOME="$tmp_home"
export XDG_DATA_HOME="$tmp_home/.local/share"
export LW_OS_OVERRIDE="unknown"   # pkg_present -> "absent" deterministically

# shellcheck disable=SC1091
source "$DIR_ROOT/lib/common.sh"

manifest_init
manifest_record_new_packages alpha beta
manifest_record_new_packages beta gamma      # beta must not duplicate
pkgs="$(manifest_cli list-packages | sort | tr '\n' ' ')"
if [[ "$pkgs" == "alpha beta gamma " ]]; then
    pass "paketler kaydedildi ve tekrarsiz."
else
    fail "paket listesi beklenenden farkli: '$pkgs'"
fi

manifest_record_service_if_new pcscd.socket
manifest_cli add-service pcscd.socket 1 1   # replaces prior entry
svc="$(manifest_cli list-services)"
if [[ "$svc" == $'pcscd.socket\t1\t1' ]]; then
    pass "servis kaydi olusturuldu ve guncellendi."
else
    fail "servis kaydi beklenenden farkli: '$svc'"
fi

manifest_record_rc "$HOME/.bashrc"          # does not exist -> ignored
if [[ -z "$(manifest_cli list-rc)" ]]; then
    pass "olmayan rc dosyasi kaydedilmedi."
else
    fail "olmayan rc dosyasi kaydedildi."
fi
: > "$HOME/.bashrc"
manifest_record_rc "$HOME/.bashrc"
if [[ "$(manifest_cli list-rc)" == "$HOME/.bashrc" ]]; then
    pass "mevcut rc dosyasi kaydedildi."
else
    fail "rc dosyasi kaydedilemedi."
fi

manifest_file="$XDG_DATA_HOME/legal-workstation/manifest.json"
if [[ -f "$manifest_file" ]] && python3 -c "import json;json.load(open('$manifest_file'))" 2>/dev/null; then
    pass "manifest gecerli JSON olarak yazildi."
else
    fail "manifest dosyasi yok veya bozuk JSON."
fi

manifest_cli delete
if [[ ! -f "$manifest_file" ]]; then
    pass "manifest silindi."
else
    fail "manifest silinmedi."
fi

echo
if [[ "$failures" -eq 0 ]]; then
    echo "==> [BASARILI] Manifesto testi tamamlandi."
    exit 0
fi
echo "==> [BASARISIZ] $failures kontrol basarisiz oldu."
exit 1
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `bash tests/test-manifest.sh`
Expected: FAIL — `manifest_init: command not found` (or `lib/manifest.py: No such file`).

- [ ] **Step 3: Create** `lib/manifest.py`

```python
#!/usr/bin/env python3
"""Install manifest for Legal Workstation.

Tracks what the installer newly added (packages, services, paths, rc files) so
that `legal-workstation uninstall --all` can remove exactly those and never a
package the user already had.

Location: ${XDG_DATA_HOME:-$HOME/.local/share}/legal-workstation/manifest.json
"""

from __future__ import annotations

import datetime
import json
import os
import sys

SCHEMA_VERSION = 1
LIST_KEYS = ("packages_added", "services_enabled", "paths", "rc_files")


def manifest_path() -> str:
    base = os.environ.get("XDG_DATA_HOME") or os.path.join(
        os.path.expanduser("~"), ".local", "share"
    )
    return os.path.join(base, "legal-workstation", "manifest.json")


def load() -> dict:
    try:
        with open(manifest_path(), encoding="utf-8") as fh:
            data = json.load(fh)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def base_doc(data: dict) -> dict:
    data.setdefault("manifest_version", SCHEMA_VERSION)
    data.setdefault(
        "installed_at",
        datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    )
    data.setdefault("os_family", os.environ.get("LW_OS_FAMILY", "unknown"))
    for key in LIST_KEYS:
        data.setdefault(key, [])
    return data


def save(data: dict) -> None:
    target = manifest_path()
    os.makedirs(os.path.dirname(target), exist_ok=True)
    tmp = target + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    os.replace(tmp, target)


def main(argv: list[str]) -> int:
    if not argv:
        print("usage: manifest.py <command> [args]", file=sys.stderr)
        return 2
    cmd, *args = argv

    if cmd == "init":
        save(base_doc(load()))

    elif cmd == "add-package":
        data = base_doc(load())
        for pkg in args:
            if pkg not in data["packages_added"]:
                data["packages_added"].append(pkg)
        save(data)

    elif cmd == "add-service":
        if len(args) != 3:
            print("add-service <unit> <was_enabled> <was_active>", file=sys.stderr)
            return 2
        unit, was_enabled, was_active = args
        data = base_doc(load())
        data["services_enabled"] = [
            s for s in data["services_enabled"] if s.get("unit") != unit
        ]
        data["services_enabled"].append(
            {
                "unit": unit,
                "was_enabled": was_enabled == "1",
                "was_active": was_active == "1",
            }
        )
        save(data)

    elif cmd == "add-path":
        data = base_doc(load())
        for item in args:
            if item not in data["paths"]:
                data["paths"].append(item)
        save(data)

    elif cmd == "add-rc":
        data = base_doc(load())
        for item in args:
            if item not in data["rc_files"]:
                data["rc_files"].append(item)
        save(data)

    elif cmd == "list-packages":
        for pkg in load().get("packages_added", []):
            print(pkg)

    elif cmd == "list-services":
        for svc in load().get("services_enabled", []):
            enabled = 1 if svc.get("was_enabled") else 0
            active = 1 if svc.get("was_active") else 0
            print(f"{svc.get('unit', '')}\t{enabled}\t{active}")

    elif cmd == "list-paths":
        for item in load().get("paths", []):
            print(item)

    elif cmd == "list-rc":
        for item in load().get("rc_files", []):
            print(item)

    elif cmd == "delete":
        try:
            os.remove(manifest_path())
        except FileNotFoundError:
            pass
        try:
            os.rmdir(os.path.dirname(manifest_path()))
        except OSError:
            pass

    else:
        print(f"unknown command: {cmd}", file=sys.stderr)
        return 2

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
```

- [ ] **Step 4: Add the `LW_OS_OVERRIDE` seam** to `detect_os` in `lib/common.sh`

Replace the opening of `detect_os` (currently starts at `detect_os() {` followed by
`    if [[ "$(uname -s)" == "Darwin" ]]; then`) with:

```bash
detect_os() {
    # Test seam: allow overriding detection without a container.
    if [[ -n "${LW_OS_OVERRIDE:-}" ]]; then
        echo "$LW_OS_OVERRIDE"
        return 0
    fi

    if [[ "$(uname -s)" == "Darwin" ]]; then
```

- [ ] **Step 5: Append the manifest helpers** to the end of `lib/common.sh`

```bash
# --- Install manifest (install-time tracking) --------------------------------
# Records what the installer newly added so `uninstall --all` can remove exactly
# those packages/services/paths without touching pre-existing software.

LW_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

manifest_cli() {
    if ! has_cmd python3; then
        log_warn "python3 bulunamadi; kurulum manifestosu kullanilamaz."
        return 1
    fi
    python3 "$LW_LIB_DIR/manifest.py" "$@"
}

# Create/merge the manifest. Uses the detected OS family for the schema record.
manifest_init() {
    LW_OS_FAMILY="$(detect_os)" manifest_cli init || true
}

# Record only packages that are not already present on the system.
manifest_record_new_packages() {
    local missing=() p
    for p in "$@"; do
        if ! pkg_present "$p"; then
            missing+=("$p")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        manifest_cli add-package "${missing[@]}" || true
    fi
}

# Record a service together with its state *before* we enable it.
manifest_record_service_if_new() {
    local unit="$1" was_enabled=0 was_active=0
    if systemctl is-enabled --quiet "$unit" 2>/dev/null; then
        was_enabled=1
    fi
    if systemctl is-active --quiet "$unit" 2>/dev/null; then
        was_active=1
    fi
    manifest_cli add-service "$unit" "$was_enabled" "$was_active" || true
}

manifest_record_rc() {
    if [[ -f "$1" ]]; then
        manifest_cli add-rc "$1" || true
    fi
}

# Is a package already installed on this system?
pkg_present() {
    local pkg="$1"
    case "$(detect_os)" in
        arch)   pacman -Qq "$pkg" >/dev/null 2>&1 ;;
        debian) dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed" ;;
        fedora) rpm -q "$pkg" >/dev/null 2>&1 ;;
        *)      return 1 ;;
    esac
}
```

- [ ] **Step 6: Run the test — it must pass**

Run: `bash tests/test-manifest.sh`
Expected: `==> [BASARILI] Manifesto testi tamamlandi.` (exit 0).

- [ ] **Step 7: Lint**

Run:
```bash
bash -n lib/manifest.py 2>/dev/null || true
bash -n lib/common.sh
python3 -m py_compile lib/manifest.py && echo "py OK"
```
Expected: `lib/common.sh` OK, `py OK`.

- [ ] **Step 8: Commit**

```bash
git add lib/manifest.py lib/common.sh tests/test-manifest.sh
git commit -m "feat: add install manifest store and helpers (tracked complete uninstall)"
```

---

## Task 2: Install-time recording in the distro engines

**Files:**
- Modify: `lib/arch.sh:9-33`, `lib/debian.sh:9-50`, `lib/fedora.sh:9-56`
- Test: extend `tests/test-manifest.sh`

- [ ] **Step 1: Add a failing assertion** at the end of `tests/test-manifest.sh`
(before the final `echo`/exit block):

```bash
# pkg_present ile kayit: 'curl' kurulu sayilsin, 'opensc' kurulu olmasin.
fakebin="$tmp_home/fakebin"; mkdir -p "$fakebin"
cat > "$fakebin/pacman" <<'PY'
#!/usr/bin/env bash
# -Qq <pkg>: pretend only "curl" is installed
[[ "$1" == "-Qq" && "$2" == "curl" ]] && { echo "curl"; exit 0; }
exit 1
PY
chmod +x "$fakebin/pacman"
export PATH="$fakebin:$PATH"
export LW_OS_OVERRIDE="arch"
manifest_cli delete
manifest_record_new_packages curl opensc
if [[ "$(manifest_cli list-packages | tr '\n' ' ')" == "opensc " ]]; then
    pass "kurulu paket atlandi, yalnizca yeni paket kaydedildi."
else
    fail "pkg_present filtrelemesi hatali: '$(manifest_cli list-packages | tr '\n' ' ')'"
fi
```

- [ ] **Step 2: Run it — must fail**

Run: `bash tests/test-manifest.sh`
Expected: FAIL on the new assertion (both `curl` and `opensc` recorded, because the
detect_os override is set *after* the earlier block already used `unknown`; the fake
`pacman` is not yet consulted because `pkg_present` for `arch` calls it — verify the
failure message mentions filtering).

- [ ] **Step 3: Record in `lib/arch.sh`**

In `arch_install_system_packages`, insert the recording call immediately before the
`sudo pacman -S ...` line, and wrap the service enable:

```bash
    log_info "Pacman paketleri kontrol ediliyor: ${pkgs[*]}"
    manifest_record_new_packages "${pkgs[@]}"
    sudo pacman -S --needed --noconfirm "${pkgs[@]}"

    log_step "2/5: PC/SC Akıllı Kart servisi etkinleştiriliyor..."
    manifest_record_service_if_new pcscd.socket
    sudo systemctl enable --now pcscd.socket pcscd.service
```

- [ ] **Step 4: Record in `lib/debian.sh`**

In `debian_install_system_packages`, before `sudo apt-get install -y -qq "${pkgs[@]}"`:

```bash
    log_info "Gerekli paketler kuruluyor: ${pkgs[*]}"
    manifest_record_new_packages "${pkgs[@]}"
    export DEBIAN_FRONTEND=noninteractive
    sudo apt-get install -y -qq "${pkgs[@]}"

    log_step "2/4: PC/SC Akıllı Kart servisi etkinleştiriliyor..."
    if has_cmd systemctl; then
        manifest_record_service_if_new pcscd.socket
        sudo systemctl enable --now pcscd.socket pcscd.service 2>/dev/null || true
    fi
```

- [ ] **Step 5: Record in `lib/fedora.sh`**

In `fedora_install_system_packages`, before `sudo dnf install -y "${pkgs[@]}"`, and record the
optional indicator + java package, plus the service:

```bash
    log_info "Paketler kontrol ediliyor: ${pkgs[*]}"
    manifest_record_new_packages "${pkgs[@]}"
    sudo dnf install -y "${pkgs[@]}"

    # Optional UI indicator
    if sudo dnf list libayatana-appindicator-gtk3 >/dev/null 2>&1; then
        manifest_record_new_packages libayatana-appindicator-gtk3
        sudo dnf install -y libayatana-appindicator-gtk3 2>/dev/null || true
    fi

    # Java 11 check: try native dnf package or fallback to isolated Temurin 11 JRE
    if sudo dnf list java-11-openjdk >/dev/null 2>&1; then
        log_info "Fedora depolarından Java 11 OpenJDK kuruluyor..."
        manifest_record_new_packages java-11-openjdk
        sudo dnf install -y java-11-openjdk
    else
```

and in the service step:

```bash
    log_step "2/5: PC/SC Akıllı Kart servisi etkinleştiriliyor..."
    if has_cmd systemctl; then
        manifest_record_service_if_new pcscd.socket
        sudo systemctl enable --now pcscd.socket pcscd.service 2>/dev/null || true
    fi
```

- [ ] **Step 6: Run the test — must pass**

Run: `bash tests/test-manifest.sh`
Expected: `==> [BASARILI] ...` (exit 0).

- [ ] **Step 7: Lint + commit**

```bash
bash -n lib/arch.sh && bash -n lib/debian.sh && bash -n lib/fedora.sh && echo OK
git add lib/arch.sh lib/debian.sh lib/fedora.sh tests/test-manifest.sh
git commit -m "feat: record newly-added packages and pcscd state at install time"
```

---

## Task 3: Enhanced safe `uninstall` (default mode)

**Files:**
- Modify: `lib/common.sh` (add `remove_local_bin_from_path`; record rc in `ensure_local_bin_on_path`)
- Modify: `bin/legal-workstation` (`cmd_uninstall`)
- Test: `tests/test-uninstall-safe.sh`

- [ ] **Step 1: Write the failing test** `tests/test-uninstall-safe.sh`

```bash
#!/usr/bin/env bash
# Legal Workstation - guvenli (varsayilan) kaldirma testi
# Dogrular: kullanicı kapsamli artiklar ve PATH kaydi temizlenir; paketlere dokunulmaz.
set -euo pipefail

DIR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failures=0
pass() { printf '  -> [GECTI] %s\n' "$1"; }
fail() { printf '  [HATA] %s\n' "$1"; failures=$((failures + 1)); }

echo "==> Guvenli kaldirma test ediliyor..."
tmp_home="$(mktemp -d /tmp/lw-uninstall-XXXXXX)"
trap 'rm -rf "$tmp_home"' EXIT
export HOME="$tmp_home"
export XDG_DATA_HOME="$tmp_home/.local/share"

fakebin="$tmp_home/fakebin"; mkdir -p "$fakebin"
# sudo: only log what it *would* run (never touch the real system)
cat > "$fakebin/sudo" <<'PY'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${SUDO_LOG:?}"
exit 0
PY
cat > "$fakebin/systemctl" <<'PY'
#!/usr/bin/env bash
exit 0
PY
# package managers must NOT be called in safe mode
cat > "$fakebin/pacman" <<'PY'
#!/usr/bin/env bash
touch "${PKG_CALLED:?}"
env "$@" 2>/dev/null || true
exit 1
PY
cat > "$fakebin/apt-get" <<'PY'
#!/usr/bin/env bash
touch "${PKG_CALLED:?}"
exit 1
PY
cat > "$fakebin/dnf" <<'PY'
#!/usr/bin/env bash
touch "${PKG_CALLED:?}"
exit 1
PY
chmod +x "$fakebin/sudo" "$fakebin/systemctl" "$fakebin/pacman" "$fakebin/apt-get" "$fakebin/dnf"
export PATH="$fakebin:$PATH"
export SUDO_LOG="$tmp_home/sudo.log"
export PKG_CALLED="$tmp_home/pkg.called"
export LW_OS_OVERRIDE="arch"

mkdir -p "$HOME/.local/share/applications" "$HOME/.local/bin" "$HOME/.local/lib"
: > "$HOME/.local/share/applications/akia.desktop"
: > "$HOME/.local/share/applications/tr.gov.adalet.eimza-tray.desktop"
: > "$HOME/.local/bin/legal-workstation"
: > "$HOME/.local/bin/uyap-dokuman"
printf '\n# Added by legal-workstation\nexport PATH="%s/.local/bin:$PATH"\n' "$HOME" >> "$HOME/.bashrc"

bash "$DIR_ROOT/bin/legal-workstation" uninstall -y >/dev/null 2>&1 || true

[[ ! -e "$HOME/.local/share/applications/akia.desktop" ]] \
    && pass "akia.desktop kaldirildi." || fail "akia.desktop kaldi."
[[ ! -e "$HOME/.local/bin/uyap-dokuman" ]] \
    && pass "uyap-dokuman kaldirildi." || fail "uyap-dokuman kaldi."
if grep -q "Added by legal-workstation" "$HOME/.bashrc"; then
    fail "PATH kaydi (~/.bashrc) temizlenmedi."
else
    pass "PATH kaydi (~/.bashrc) temizlendi."
fi
[[ ! -e "$PKG_CALLED" ]] \
    && pass "guvenli modda paket yoneticisi cagrilmadi." || fail "guvenli modda paket yoneticisi cagrildi!"

# Sistema ait yollar (sudo ile) loglandi mi?
for want in "/opt/Akia" "/usr/local/bin/akia" "/usr/share/java/uyap-editor" "/usr/share/applications/akia.desktop"; do
    if grep -q -- "$want" "$SUDO_LOG" 2>/dev/null; then
        pass "sudo temizligi planlandi: $want"
    else
        fail "sudo temizligi eksik: $want"
    fi
done

echo
if [[ "$failures" -eq 0 ]]; then
    echo "==> [BASARILI] Guvenli kaldirma testi tamamlandi."
    exit 0
fi
echo "==> [BASARISIZ] $failures kontrol basarisiz oldu."
exit 1
```

- [ ] **Step 2: Run it — must fail**

Run: `bash tests/test-uninstall-safe.sh`
Expected: FAIL on `akia.desktop`, the PATH marker, and the missing `/opt/Akia` sudo plan.

- [ ] **Step 3: Add helpers** to `lib/common.sh`

Extend `ensure_local_bin_on_path` so each rc file it edits is recorded — inside the loop,
right after the append:

```bash
        printf '\n%s\n%s\n' "$marker" "$export_line" >> "$rc"
        log_info "$bin_dir kabuk PATH'ine eklendi: $rc"
        manifest_record_rc "$rc"
```

and in the fallback branch:

```bash
    if [[ "$updated_any" != true ]]; then
        printf '%s\n%s\n' "$marker" "$export_line" >> "$HOME/.profile"
        log_info "$bin_dir kabuk PATH'ine eklendi: $HOME/.profile"
        manifest_record_rc "$HOME/.profile"
    fi
```

Append the inverse helper at the end of `lib/common.sh`:

```bash
# Remove the "# Added by legal-workstation" marker and the PATH export line that
# follows it from the user's shell rc files. Idempotent and safe on any file.
remove_local_bin_from_path() {
    local marker="# Added by legal-workstation"
    local rc tmp
    for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
        [[ -f "$rc" ]] || continue
        if ! grep -qF "$marker" "$rc" 2>/dev/null; then
            continue
        fi
        tmp="$(mktemp)"
        awk -v m="$marker" '
            $0 == m { skip = 1; next }
            skip && /^export PATH=/ { skip = 0; next }
            { skip = 0; print }
        ' "$rc" > "$tmp" && mv "$tmp" "$rc"
    done
}
```

- [ ] **Step 4: Rewrite `cmd_uninstall`** in `bin/legal-workstation`

Replace the whole existing `cmd_uninstall()` (lines 208-297) with:

```bash
cmd_uninstall() {
    shift # drop the "uninstall"/"remove" verb
    local force=false all=false arg
    for arg in "$@"; do
        case "$arg" in
            -y|--yes) force=true ;;
            --all) all=true ;;
        esac
    done

    if [[ "$force" != true ]]; then
        printf "${YELLOW}${BOLD}DİKKAT:${NC} Bu işlem Legal Workstation tarafından kurulan servisleri, başlatıcıları ve dosyaları kaldırır.\n"
        if [[ "$all" == true ]]; then
            printf "Tam kaldırma (--all): Kurulum sırasında ${BOLD}bu araç tarafından yeni eklenen${NC} sistem paketleri ve servisler de kaldırılacaktır.\n\n"
        else
            printf "Güvenli mod: Önceden veya manuel kurulu genel sistem paketlerinize dokunulmaz.\n"
            printf "Kurulumda eklenen sistem paketlerini de kaldırmak için: ${CYAN}legal-workstation uninstall --all${NC}\n\n"
        fi
        read -r -p "Kaldırma işlemine devam etmek istiyor musunuz? [e/H] " confirm
        if [[ "$confirm" != "e" && "$confirm" != "E" && "$confirm" != "y" && "$confirm" != "Y" ]]; then
            log_info "Kaldırma işlemi iptal edildi."
            exit 0
        fi
        if [[ "$all" == true ]]; then
            read -r -p "Sistem paketleri de kaldırılacak. Onaylamak için 'TUMU' yazın: " confirm_all
            if [[ "$confirm_all" != "TUMU" && "$confirm_all" != "ALL" ]]; then
                log_info "Tam kaldırma iptal edildi."
                exit 0
            fi
        fi
    fi

    if [[ "$(uname -s)" == "Darwin" ]]; then
        log_step "macOS Legal Workstation kaldırılıyor..."

        log_info "1/3: Çalışan süreçler ve başlangıç öğeleri temizleniyor..."
        pkill -f "adalet-eimza-tray" 2>/dev/null || true
        osascript -e 'tell application "System Events" to delete login item "Adalet E-İmza Tray"' 2>/dev/null || true

        log_info "2/3: Uygulamalar kaldırılıyor..."
        sudo rm -rf "/Applications/Adalet E-İmza Tray.app" 2>/dev/null || true
        sudo rm -rf "/Applications/UyapDokumanEditoru.app" 2>/dev/null || true
        sudo rm -rf "/Applications/PTT UETS E-İmza.app" /opt/uets /usr/local/bin/uets-eimza 2>/dev/null || true

        log_info "3/3: legal-workstation CLI aracı kaldırılıyor..."
        sudo rm -f "/usr/local/bin/legal-workstation" "$HOME/.local/bin/legal-workstation" 2>/dev/null || true

        if [[ "$all" == true ]]; then
            log_warn "Tam kaldırma (--all) bu platformda henüz desteklenmiyor; güvenli kaldırma uygulandı."
        fi

        log_success "macOS Legal Workstation başarıyla kaldırıldı. Sisteminiz temizlendi."
        return 0
    fi

    log_step "Hukuk Çalışma İstasyonu kaldırılıyor..."

    # 1. Stop and disable Adalet E-İmza tray service
    log_info "1/5: Arka plan servisleri durduruluyor ve temizleniyor..."
    if has_cmd systemctl; then
        systemctl --user stop adalet-eimza-tray.service 2>/dev/null || true
        systemctl --user disable adalet-eimza-tray.service 2>/dev/null || true
    fi
    rm -f "$HOME/.config/systemd/user/adalet-eimza-tray.service"
    if has_cmd systemctl; then
        systemctl --user daemon-reload 2>/dev/null || true
    fi

    # 2. Remove desktop entries and launchers created by suite
    log_info "2/5: Masaüstü kısayolları ve başlatıcılar kaldırılıyor..."
    rm -f "$HOME/.local/share/applications/tr.gov.adalet.eimza-tray.desktop"
    rm -f "$HOME/.local/share/applications/uyap-dokuman.desktop"
    rm -f "$HOME/.local/share/applications/uets.desktop"
    rm -f "$HOME/.local/share/applications/akia.desktop"
    rm -f "$HOME/.local/share/icons/adalet-eimza-tray."* 2>/dev/null || true
    if [[ -w /usr/share/applications ]] || has_cmd sudo; then
        sudo rm -f "/usr/share/applications/uets.desktop" 2>/dev/null || true
        sudo rm -f "/usr/share/applications/akia.desktop" 2>/dev/null || true
    fi

    # 3. Remove suite-specific binaries and libraries
    log_info "3/5: Uygulama ve kütüphaneler temizleniyor..."
    rm -f "$HOME/.local/bin/uyap-dokuman"
    rm -f "$HOME/.local/bin/adalet-eimza-tray"
    rm -f "$HOME/.local/bin/check-adalet-eimza-update"
    rm -rf "$HOME/.local/lib/adalet-eimza-tray"
    rm -f "$HOME/.local/lib/libakisp11.so"
    rm -f "$HOME/.local/lib/libopensc-pkcs11.so"
    rm -f "$HOME/.local/lib/libappindicator3"* 2>/dev/null || true

    # Clean system-level AKİA and UYAP artifacts created by the suite
    if has_cmd sudo; then
        sudo rm -f /usr/local/bin/akia /usr/lib/libakisp11.so 2>/dev/null || true
        sudo rm -rf /opt/Akia 2>/dev/null || true
        sudo rm -rf /usr/share/java/uyap-editor 2>/dev/null || true
    fi

    # Clean UETS if installed by suite
    if [[ -d /opt/uets || -f /usr/local/bin/uets-eimza ]]; then
        log_info "PTT UETS E-İmza istemcisi temizleniyor..."
        sudo rm -rf /opt/uets /usr/local/bin/uets-eimza 2>/dev/null || true
    fi

    # Remove isolated Temurin JRE if installed exclusively by suite
    if [[ -d "$HOME/.local/share/jvm/temurin-11" ]]; then
        log_info "İzole Temurin Java 11 JRE temizleniyor..."
        rm -rf "$HOME/.local/share/jvm/temurin-11"
    fi

    # 4. Remove the ~/.local/bin PATH entry we added at install time
    log_info "4/5: Kabuk PATH kaydı temizleniyor..."
    remove_local_bin_from_path

    # 5. Remove CLI tool itself
    log_info "5/5: legal-workstation CLI aracı kaldırılıyor..."
    local self_bin="$HOME/.local/bin/legal-workstation"
    if [[ -f "$self_bin" ]]; then
        rm -f "$self_bin"
    fi

    if [[ "$all" == true ]]; then
        uninstall_complete
    fi

    log_success "Hukuk Çalışma İstasyonu başarıyla kaldırıldı. Sisteminiz temizlendi."
}
```

- [ ] **Step 5: Run the test — must pass**

Run: `bash tests/test-uninstall-safe.sh`
Expected: `==> [BASARILI] Guvenli kaldirma testi tamamlandi.` (exit 0).

- [ ] **Step 6: Ensure the existing PATH test still passes**

Run: `bash tests/test-local-bin-path.sh`
Expected: PASS (the added `manifest_record_rc` writes into the temp HOME).

- [ ] **Step 7: Lint + commit**

```bash
bash -n bin/legal-workstation && bash -n lib/common.sh && echo OK
git add lib/common.sh bin/legal-workstation tests/test-uninstall-safe.sh
git commit -m "feat: complete safe uninstall (AKIA/UYAP artifacts, PATH entry) and record rc files"
```

---

## Task 4: `uninstall --all` complete mode

**Files:**
- Modify: `bin/legal-workstation` (add `uninstall_complete`, wire into `cmd_uninstall`)
- Test: `tests/test-uninstall-all.sh`

- [ ] **Step 1: Write the failing test** `tests/test-uninstall-all.sh`

```bash
#!/usr/bin/env bash
# Legal Workstation - tam kaldirma (--all) testi
# Dogrular: yalnizca manifestoda kayitli paketler/servisler hedeflenir; manifesto silinir;
# manifesto yoksa paket kaldirma reddedilir.
set -euo pipefail

DIR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failures=0
pass() { printf '  -> [GECTI] %s\n' "$1"; }
fail() { printf '  [HATA] %s\n' "$1"; failures=$((failures + 1)); }

echo "==> Tam kaldirma (--all) test ediliyor..."

run_all() {
    local home_dir="$1" log="$2"
    HOME="$home_dir" XDG_DATA_HOME="$home_dir/.local/share" \
        SUDO_LOG="$log" LW_OS_OVERRIDE="arch" \
        bash "$DIR_ROOT/bin/legal-workstation" uninstall --all -y >/dev/null 2>&1 || true
}

# --- Case 1: manifest present, package removal targeted ---
tmp_home="$(mktemp -d /tmp/lw-all-XXXXXX)"
trap 'rm -rf "$tmp_home"' EXIT
fakebin="$tmp_home/fakebin"; mkdir -p "$fakebin"
cat > "$fakebin/sudo" <<'PY'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${SUDO_LOG:?}"
exit 0
PY
cat > "$fakebin/systemctl" <<'PY'
#!/usr/bin/env bash
exit 0
PY
chmod +x "$fakebin/sudo" "$fakebin/systemctl"
export PATH="$fakebin:$PATH"

mkdir -p "$tmp_home/.local/share/legal-workstation"
cat > "$tmp_home/.local/share/legal-workstation/manifest.json" <<'JSON'
{
  "manifest_version": 1,
  "installed_at": "2026-10-16T00:00:00Z",
  "os_family": "arch",
  "packages_added": ["opensc", "ccid", "pcsc-tools"],
  "services_enabled": [{"unit": "pcscd.socket", "was_enabled": false, "was_active": false}],
  "paths": ["/opt/Akia", "/usr/share/java/uyap-editor"],
  "rc_files": []
}
JSON

log="$tmp_home/sudo.log"
run_all "$tmp_home" "$log"

for want in "pacman -Rs --noconfirm opensc ccid pcsc-tools" \
            "systemctl disable pcscd.socket" \
            "systemctl stop pcscd.socket" \
            "/usr/share/java/uyap-editor"; do
    if grep -q -- "$want" "$log" 2>/dev/null; then
        pass "hedeflendi: $want"
    else
        fail "hedeflenmedi: $want"
    fi
done

if grep -q "pacman" "$log" && grep -q "curl" "$log"; then
    fail "kayitli olmayan paketler de hedeflendi."
else
    pass "yalnizca kayitli paketler hedeflendi (curl gibi paketler yok)."
fi

if [[ ! -f "$tmp_home/.local/share/legal-workstation/manifest.json" ]]; then
    pass "manifesto --all sonrasi silindi."
else
    fail "manifesto silinmedi."
fi

# --- Case 2: no manifest -> refuse package/service removal ---
home2="$(mktemp -d /tmp/lw-all-empty-XXXXXX)"
trap 'rm -rf "$tmp_home" "$home2"' EXIT
log2="$home2/sudo.log"
run_all "$home2" "$log2"
if grep -q "pacman" "$log2" 2>/dev/null; then
    fail "manifesto yokken paket kaldirma denendi."
else
    pass "manifesto yok: paket/servis kaldirma reddedildi."
fi

echo
if [[ "$failures" -eq 0 ]]; then
    echo "==> [BASARILI] Tam kaldirma testi tamamlandi."
    exit 0
fi
echo "==> [BASARISIZ] $failures kontrol basarisiz oldu."
exit 1
```

- [ ] **Step 2: Run it — must fail**

Run: `bash tests/test-uninstall-all.sh`
Expected: FAIL — `uninstall_complete: command not found` / no `pacman -Rs` in the log.

- [ ] **Step 3: Add `uninstall_complete`** to `bin/legal-workstation`, immediately before
`cmd_uninstall()`:

```bash
# Complete removal (--all): revert services we enabled and remove only the
# packages recorded as newly added at install time.
uninstall_complete() {
    if ! has_cmd python3; then
        log_warn "python3 bulunamadı; tam kaldırma (paket temizliği) atlanıyor."
        return 0
    fi

    local pkgs
    pkgs="$(manifest_cli list-packages 2>/dev/null || true)"
    if [[ -z "$pkgs" ]]; then
        log_warn "Kurulum manifestosu bulunamadı; sistem paketleri ve servisler korunuyor."
        manifest_cli delete 2>/dev/null || true
        return 0
    fi

    log_step "Tam kaldırma: kurulumda eklenen sistem paketleri ve servisler kaldırılıyor..."

    # Revert services only where we changed the state
    local unit was_enabled was_active
    while IFS=$'\t' read -r unit was_enabled was_active; do
        [[ -n "$unit" ]] || continue
        if [[ "$was_enabled" == "0" ]]; then
            sudo systemctl disable "$unit" 2>/dev/null || true
        fi
        if [[ "$was_active" == "0" ]]; then
            sudo systemctl stop "$unit" 2>/dev/null || true
        fi
    done < <(manifest_cli list-services 2>/dev/null || true)

    # Remove exactly the packages recorded as newly added
    local -a pkg_list
    mapfile -t pkg_list <<< "$pkgs"
    case "$(detect_os)" in
        arch)   sudo pacman -Rs --noconfirm "${pkg_list[@]}" ;;
        debian) sudo apt-get remove -y "${pkg_list[@]}" && sudo apt-get autoremove -y ;;
        fedora) sudo dnf remove -y "${pkg_list[@]}" ;;
        *)      log_warn "Bu platformda paket temizliği desteklenmiyor." ;;
    esac

    # Remaining recorded system paths
    local path
    while IFS= read -r path; do
        [[ -n "$path" ]] || continue
        sudo rm -rf "$path" 2>/dev/null || true
    done < <(manifest_cli list-paths 2>/dev/null || true)

    manifest_cli delete 2>/dev/null || true
    log_success "Tam kaldırma tamamlandı."
}
```

(`manifest_cli`, `has_cmd`, `detect_os` are available: the CLI sources `lib/common.sh`,
or falls back to inline `has_cmd` only. `manifest_cli` requires `common.sh`; see Task 5
which installs it alongside the CLI. In-repo runs always have it.)

- [ ] **Step 4: Run the test — must pass**

Run: `bash tests/test-uninstall-all.sh`
Expected: `==> [BASARILI] Tam kaldirma testi tamamlandi.` (exit 0).

- [ ] **Step 5: Lint + commit**

```bash
bash -n bin/legal-workstation && echo OK
git add bin/legal-workstation tests/test-uninstall-all.sh
git commit -m "feat: add uninstall --all (remove tracked packages and revert services)"
```

---

## Task 5: Wire the installer (manifest init, ship lib files)

**Files:**
- Modify: `install.sh`
- Test: `tests/test-bootstrap-smoke.sh` (existing) + manual dry-run

- [ ] **Step 1: Init the manifest and ship the library files** in `install.sh` `main()`

After the `case "$target_os" in ... esac` block (i.e. after the OS engine has run) and just
before the `if [[ "$DRY_RUN" == "1" ]]` check, insert:

```bash
    # Record/refresh the install manifest for tracked complete uninstall
    [[ "$DRY_RUN" == "1" ]] || manifest_init
```

Then in the block that installs the CLI (replace the three existing lines that `mkdir -p`,
`cp`, `chmod`):

```bash
    # Install the CLI and the shared library it depends on at runtime
    mkdir -p "$HOME/.local/bin" "$HOME/.local/lib"
    cp -f "$DIR_ROOT/lib/common.sh" "$HOME/.local/lib/common.sh"
    cp -f "$DIR_ROOT/lib/manifest.py" "$HOME/.local/lib/manifest.py"
    cp -f "$DIR_ROOT/bin/legal-workstation" "$HOME/.local/bin/legal-workstation"
    chmod +x "$HOME/.local/bin/legal-workstation"
    ensure_local_bin_on_path
```

- [ ] **Step 2: Record the installed CLI path** — in the manifest init block you just added,
also record the CLI path. Change it to:

```bash
    # Record/refresh the install manifest for tracked complete uninstall
    if [[ "$DRY_RUN" != "1" ]]; then
        manifest_init
        manifest_cli add-path "$HOME/.local/bin/legal-workstation" || true
    fi
```

- [ ] **Step 3: Verify the dry run is unaffected**

Run: `LW_DRY_RUN=1 bash install.sh`
Expected: no manifest written (check `~/.local/share/legal-workstation/manifest.json` is
untouched), output ends with the dry-run notice, exit 0.

- [ ] **Step 4: Run the bootstrap smoke test**

Run: `bash tests/test-bootstrap-smoke.sh`
Expected: `==> [BASARILI] Bootstrap duman testi tamamlandi.`

- [ ] **Step 5: Commit**

```bash
bash -n install.sh && echo OK
git add install.sh
git commit -m "feat: init manifest and ship common.sh/manifest.py for complete uninstall"
```

---

## Task 6: Docs + CI

**Files:**
- Modify: `.github/workflows/ci.yml`, `README.md`, `CHANGELOG.md`

- [ ] **Step 1: Run the new tests in CI** — in `.github/workflows/ci.yml`, after the existing
`~/.local/bin PATH integration test` step, add:

```yaml
      - name: Install manifest test
        run: bash tests/test-manifest.sh

      - name: Safe uninstall test
        run: bash tests/test-uninstall-safe.sh

      - name: Complete uninstall (--all) test
        run: bash tests/test-uninstall-all.sh
```

- [ ] **Step 2: Document the two modes** in `README.md` — replace the section body at
`README.md:144-155` with:

```markdown
## 🗑️ Güvenli ve Temiz Kaldırma (`uninstall`)

Kurulum paketinin kurduğu servisleri, masaüstü kısayollarını ve başlatıcıları kaldırmak için:

```bash
legal-workstation uninstall
```

Kurulum sırasında **bu araç tarafından yeni eklenen sistem paketlerini ve servisleri de**
(ör. `pcscd`, kart okuyucu kütüphaneleri) kaldırmak için tam kaldırma modunu kullanın:

```bash
legal-workstation uninstall --all
```

> [!NOTE]
> **Güvenlik ve İzolasyon İlkesi:** `uninstall` yalnızca bu aracın oluşturduğu dosyaları
> temizler; sistem paketlerinize dokunmaz. `uninstall --all` ise **yalnızca kurulum sırasında
> araç tarafından yeni eklenmiş** paketleri kaldırır (kurulum anında kaydedilen bir manifesto
> ile). Önceden veya manuel olarak kurduğunuz paketler, sürücüler ve kişisel dosyalarınız asla
> kaldırılmaz. `--all` ek bir onay ister (`TUMU` yazın veya `-y` kullanın).
```

- [ ] **Step 3: Update `CHANGELOG.md`** — under `## [Unreleased]` → `### Added`, add:

```markdown
- **Complete uninstall (`legal-workstation uninstall --all`)**: removes exactly the system
  packages and services the installer newly added, using an install-time manifest
  (`~/.local/share/legal-workstation/manifest.json`). Pre-existing packages are never touched.
- Default `uninstall` now also removes AKİA artifacts (`akia.desktop`, `/opt/Akia`,
  `/usr/local/bin/akia`, `/usr/lib/libakisp11.so`), the UYAP editor libraries
  (`/usr/share/java/uyap-editor`), and the `~/.local/bin` PATH entry it added.
- `lib/manifest.py` plus `manifest_*` helpers in `lib/common.sh` for install-time tracking.
- `tests/test-manifest.sh`, `tests/test-uninstall-safe.sh`, `tests/test-uninstall-all.sh`,
  wired into CI.
```

- [ ] **Step 4: Lint the workflow + full local test sweep**

Run:
```bash
for f in install.sh install-macos.sh bin/legal-workstation lib/*.sh tests/*.sh; do bash -n "$f" || exit 1; done && echo "syntax OK"
bash tests/test-manifest.sh && bash tests/test-uninstall-safe.sh && bash tests/test-uninstall-all.sh && bash tests/test-local-bin-path.sh && bash tests/test-bootstrap-smoke.sh && echo "ALL TESTS OK"
```
Expected: `syntax OK` and `ALL TESTS OK`.

- [ ] **Step 5: ShellCheck (errors blocking)** via Docker

Run:
```bash
docker run --rm -v "$PWD:/mnt" -w /mnt koalaman/shellcheck:stable --severity=error \
    install.sh install-macos.sh lib/*.sh bin/legal-workstation tests/*.sh
```
Expected: no output, exit 0.

- [ ] **Step 6: Commit**

```bash
git add .github/workflows/ci.yml README.md CHANGELOG.md
git commit -m "docs+ci: document uninstall vs uninstall --all and run new tests"
```

---

## Self-Review

**Spec coverage:**
- §4 command surface → Task 3 (parsing) + Task 4 (`--all`). ✓
- §5 manifest schema/location/atomic write → Task 1 (`lib/manifest.py`). ✓
- §6 install-time recording → Task 2 + Task 3 (`ensure_local_bin_on_path` rc recording) +
  Task 5 (`manifest_init`). ✓
- §7 enhanced safe uninstall → Task 3. ✓
- §8 complete sequence → Task 4. ✓
- §9 safety (missing manifest, only recorded packages, only services we enabled, confirmation)
  → Task 4 (`-y`/`TUMU`) + test Case 2. ✓
- §10 upgrade merge → merge is inherent in `manifest.py add-*` (idempotent) + `manifest_init`;
  `cmd_upgrade` re-runs install steps, so no extra task needed. ✓
- §11 cross-platform posture → macOS path prints "not yet available" (Task 3). ✓
- §12 testing → Tasks 1/3/4 + CI (Task 6). ✓
- §13 files touched → all listed files appear in tasks. ✓

**Placeholder scan:** no `TODO`/`...`/"similar to Task N" left; every code block is complete.

**Type/name consistency:** bash `manifest_cli` ↔ `lib/manifest.py` subcommands
(`init`, `add-package`, `add-service`, `add-path`, `add-rc`, `list-packages`,
`list-services`, `list-paths`, `list-rc`, `delete`) match across Tasks 1–5. Helper names
(`manifest_init`, `manifest_record_new_packages`, `manifest_record_service_if_new`,
`manifest_record_rc`, `pkg_present`, `remove_local_bin_from_path`, `uninstall_complete`)
are used identically wherever referenced.

**Known gap (documented, not a bug):** package removal happens via the distro manager's own
dependency handling (`pacman -Rs`, `apt autoremove`, `dnf remove`); transitive dependencies
pulled in by our packages may or may not be removed depending on whether other software needs
them — which is the safe behaviour.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-10-16-complete-uninstall.md`.
Two execution options:

1. **Subagent-Driven (recommended)** — dispatch a fresh subagent per task, review between tasks.
2. **Inline Execution** — execute tasks in this session with checkpoints.

Which approach?
