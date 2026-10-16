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
: > "$HOME/.local/lib/common.sh"
: > "$HOME/.local/lib/manifest.py"
printf '\n# Added by legal-workstation\nexport PATH="%s/.local/bin:$PATH"\n' "$HOME" >> "$HOME/.bashrc"

# Kurulum manifestosu: guvenli kaldirma, sistem yollarini YALNIZCA kurulumda
# kayitliysa siler. Bu yollari burada kaydediyoruz ki olumlu kontroller gecsin.
mkdir -p "$XDG_DATA_HOME/legal-workstation"
cat > "$XDG_DATA_HOME/legal-workstation/manifest.json" <<'JSON'
{
  "manifest_version": 1,
  "installed_at": "2026-10-16T00:00:00Z",
  "os_family": "arch",
  "packages_added": [],
  "services_enabled": [],
  "paths": ["/opt/Akia", "/usr/local/bin/akia", "/usr/lib/libakisp11.so", "/usr/share/java/uyap-editor", "/usr/share/applications/akia.desktop"],
  "rc_files": []
}
JSON

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

# Kaldirma sonunda dagitilan kutuphane dosyalari temizlenmis olmali.
if [[ ! -e "$HOME/.local/lib/common.sh" && ! -e "$HOME/.local/lib/manifest.py" ]]; then
    pass "dagitilan kutuphane dosyalari (~/.local/lib) kaldirildi."
else
    fail "dagitilan kutuphane dosyalari kaldirilmadi."
fi

# Sistema ait yollar (sudo ile) loglandi mi?
for want in "/opt/Akia" "/usr/local/bin/akia" "/usr/share/java/uyap-editor" "/usr/share/applications/akia.desktop"; do
    if grep -q -- "$want" "$SUDO_LOG" 2>/dev/null; then
        pass "sudo temizligi planlandi: $want"
    else
        fail "sudo temizligi eksik: $want"
    fi
done

# --- Negatif durum: manifesto yoksa onceden var olan sistem yazilimina DOKUNULMAMALI ---
neg_home="$(mktemp -d /tmp/lw-uninstall-neg-XXXXXX)"
trap 'rm -rf "$tmp_home" "$neg_home"' EXIT
mkdir -p "$neg_home/.local/share/applications" "$neg_home/.local/bin" "$neg_home/.local/lib"
neg_log="$neg_home/sudo.log"
HOME="$neg_home" XDG_DATA_HOME="$neg_home/.local/share" SUDO_LOG="$neg_log" LW_OS_OVERRIDE=arch \
    PATH="$fakebin:$PATH" bash "$DIR_ROOT/bin/legal-workstation" uninstall -y >/dev/null 2>&1 || true

for absent in "/opt/Akia" "/usr/share/java/uyap-editor" "/usr/local/bin/akia" "/usr/lib/libakisp11.so" \
              "/usr/share/applications/akia.desktop" "/usr/share/applications/uets.desktop"; do
    if grep -qF -- "$absent" "$neg_log" 2>/dev/null; then
        fail "manifesto yokken onceden var olan yola dokunuldu: $absent"
    else
        pass "manifesto yok: korundu: $absent"
    fi
done

# --- I3: symlink'li rc (dotfiles) korunmali; marker hedefte temizlenmeli ---
lnk_home="$(mktemp -d /tmp/lw-uninstall-link-XXXXXX)"
trap 'rm -rf "$tmp_home" "$neg_home" "$lnk_home"' EXIT
mkdir -p "$lnk_home/.local/bin" "$lnk_home/.local/lib" "$lnk_home/dotfiles"
printf 'alias ll="ls -l"\n\n# Added by legal-workstation\nexport PATH="%s/.local/bin:$PATH"\n' \
    "$lnk_home" > "$lnk_home/dotfiles/bashrc"
ln -s "$lnk_home/dotfiles/bashrc" "$lnk_home/.bashrc"
HOME="$lnk_home" XDG_DATA_HOME="$lnk_home/.local/share" SUDO_LOG="$lnk_home/sudo.log" LW_OS_OVERRIDE=arch \
    PATH="$fakebin:$PATH" bash "$DIR_ROOT/bin/legal-workstation" uninstall -y >/dev/null 2>&1 || true
if [[ -L "$lnk_home/.bashrc" ]]; then
    pass "symlink'li ~/.bashrc korundu."
else
    fail "symlink'li ~/.bashrc normal dosyaya donusturuldu (dotfiles kirildi)."
fi
if grep -q 'Added by legal-workstation' "$lnk_home/dotfiles/bashrc" 2>/dev/null; then
    fail "symlink hedefinde PATH marker kaldi."
else
    pass "symlink hedefindeki PATH marker temizlendi."
fi

# --- I3b: CRLF satir sonlari olan rc'de marker temizlenmeli ---
crlf_home="$(mktemp -d /tmp/lw-uninstall-crlf-XXXXXX)"
trap 'rm -rf "$tmp_home" "$neg_home" "$lnk_home" "$crlf_home"' EXIT
mkdir -p "$crlf_home/.local/bin" "$crlf_home/.local/lib"
printf 'alias ll="ls -l"\r\n# Added by legal-workstation\r\nexport PATH="%s/.local/bin:$PATH"\r\n' \
    "$crlf_home" > "$crlf_home/.bashrc"
HOME="$crlf_home" XDG_DATA_HOME="$crlf_home/.local/share" SUDO_LOG="$crlf_home/sudo.log" LW_OS_OVERRIDE=arch \
    PATH="$fakebin:$PATH" bash "$DIR_ROOT/bin/legal-workstation" uninstall -y >/dev/null 2>&1 || true
if grep -q 'Added by legal-workstation' "$crlf_home/.bashrc" 2>/dev/null; then
    fail "CRLF satir sonlarinda PATH marker temizlenemedi."
else
    pass "CRLF satir sonlarinda PATH marker temizlendi."
fi

echo
if [[ "$failures" -eq 0 ]]; then
    echo "==> [BASARILI] Guvenli kaldirma testi tamamlandi."
    exit 0
fi
echo "==> [BASARISIZ] $failures kontrol basarisiz oldu."
exit 1
