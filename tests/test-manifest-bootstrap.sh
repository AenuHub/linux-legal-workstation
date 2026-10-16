#!/usr/bin/env bash
# Legal Workstation - taze sistem manifest bootstrap testi (C1)
#
# Taze bir sistemde python3 HENUZ YOKKEN ilk kayit cagrilari sessizce
# basarisiz oluyordu; bu yuzden taban paketler manifestoya yazilmiyor ve
# `uninstall --all` bu paketleri geride birakiyordu.
#
# Dogrular: manifest_bootstrap python3'u bootstrap eder, manifestoyu os_family
# ile birlikte kurar ve python3'u (yalnizca yeni eklendiyse) kaydeder.
set -euo pipefail

DIR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failures=0
pass() { printf '  -> [GECTI] %s\n' "$1"; }
fail() { printf '  [HATA] %s\n' "$1"; failures=$((failures + 1)); }

echo "==> Taze sistem manifest bootstrap test ediliyor..."

real_py="$(command -v python3)"
real_ln="$(command -v ln)"
real_bash="$(command -v bash)"

tmp_home="$(mktemp -d /tmp/lw-boot-XXXXXX)"
trap 'rm -rf "$tmp_home"' EXIT
export HOME="$tmp_home"
export XDG_DATA_HOME="$tmp_home/.local/share"

# Taze sistem benzetimi: PATH yalnizca shim dizinini icerir ve python3 YOKTUR.
shim="$tmp_home/shim"; mkdir -p "$shim"
ln -s "$real_ln" "$shim/ln"
ln -s "$(command -v dirname)" "$shim/dirname"
ln -s "$(command -v grep)" "$shim/grep"
# apt-get "python3 kurunca" shim'e gercek python3'u baglar.
cat > "$shim/apt-get" <<PY
#!/bin/bash
for a in "\$@"; do
    if [[ "\$a" == "python3" ]]; then ln -sf "$real_py" "$shim/python3"; fi
done
exit 0
PY
# pkg_present (debian): yalnizca curl kurulu sayilsin.
cat > "$shim/dpkg-query" <<'PY'
#!/bin/bash
for a in "$@"; do
    if [[ "$a" == "curl" ]]; then echo "install ok installed"; exit 0; fi
done
echo "not-installed"
exit 1
PY
chmod +x "$shim/apt-get" "$shim/dpkg-query"

out=""
rc=0
out="$(
    PATH="$shim" HOME="$HOME" XDG_DATA_HOME="$XDG_DATA_HOME" LW_OS_OVERRIDE=debian \
    "$real_bash" -c '
        set -euo pipefail
        source "$1/lib/common.sh"
        require_sudo() { :; }
        sudo() { "$@"; }
        # python3 taze sistemde yok:
        command -v python3 >/dev/null && echo "PY_BEFORE=present" || echo "PY_BEFORE=absent"
        manifest_bootstrap
        command -v python3 >/dev/null && echo "PY_AFTER=present" || echo "PY_AFTER=absent"
        manifest_record_new_packages opensc curl
        while IFS= read -r p; do echo "PKG:$p"; done < <(manifest_cli list-packages)
        echo "OSF:$(python3 -c "import json,os;p=os.path.join(os.environ[\"XDG_DATA_HOME\"],\"legal-workstation\",\"manifest.json\");print(json.load(open(p))[\"os_family\"])")"
    ' _ "$DIR_ROOT" 2>/dev/null
)" || rc=$?

if [[ "$rc" -ne 0 ]]; then
    fail "manifest_bootstrap taze sistemde hata verdi (rc=$rc)."
    printf '%s\n' "$out" | sed 's/^/        /'
    echo
    echo "==> [BASARISIZ] $failures kontrol basarisiz oldu."
    exit 1
fi

grep -q '^PY_BEFORE=absent$' <<<"$out" \
    && pass "python3 taze sistemde yok (test kurgusu dogru)." \
    || fail "test kurgusu: python3 bastan var gorunuyor."
grep -q '^PY_AFTER=present$' <<<"$out" \
    && pass "manifest_bootstrap python3'u bootstrap etti." \
    || fail "python3 bootstrap edilemedi."
grep -q '^OSF:debian$' <<<"$out" \
    && pass "manifesto os_family ile kuruldu (unknown degil)." \
    || fail "os_family yanlis: $(grep '^OSF:' <<<"$out")"
grep -q '^PKG:python3$' <<<"$out" \
    && pass "yeni eklenen python3 manifestoya kaydedildi." \
    || fail "python3 manifestoya kaydedilmedi."
grep -q '^PKG:opensc$' <<<"$out" \
    && pass "taban paket (opensc) taze sistemde kaydedildi." \
    || fail "taban paket kaydedilmedi (C1 regresyonu)."
grep -q '^PKG:curl$' <<<"$out" \
    && fail "kurulu paket (curl) yanlislikla kaydedildi." \
    || pass "kurulu paket (curl) atlandi."

echo
if [[ "$failures" -eq 0 ]]; then
    echo "==> [BASARILI] Taze sistem manifest bootstrap testi tamamlandi."
    exit 0
fi
echo "==> [BASARISIZ] $failures kontrol basarisiz oldu."
exit 1
