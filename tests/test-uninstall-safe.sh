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
