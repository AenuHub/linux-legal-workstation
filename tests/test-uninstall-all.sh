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
  "services_enabled": [
    {"unit": "pcscd.socket", "was_enabled": false, "was_active": false},
    {"unit": "pcscd.service", "was_enabled": false, "was_active": false}
  ],
  "paths": ["/opt/Akia", "/usr/share/java/uyap-editor"],
  "rc_files": []
}
JSON

log="$tmp_home/sudo.log"
run_all "$tmp_home" "$log"

for want in "pacman -Rs --noconfirm opensc ccid pcsc-tools" \
            "systemctl disable pcscd.socket" \
            "systemctl stop pcscd.socket" \
            "systemctl disable pcscd.service" \
            "systemctl stop pcscd.service" \
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

# --- Case 3: empty packages_added but service + path recorded -> still revert/remove ---
home3="$(mktemp -d /tmp/lw-all-svconly-XXXXXX)"
trap 'rm -rf "$tmp_home" "$home2" "$home3" "$home4"' EXIT
mkdir -p "$home3/.local/share/legal-workstation"
cat > "$home3/.local/share/legal-workstation/manifest.json" <<'JSON'
{
  "manifest_version": 1,
  "installed_at": "2026-10-16T00:00:00Z",
  "os_family": "arch",
  "packages_added": [],
  "services_enabled": [{"unit": "pcscd.socket", "was_enabled": false, "was_active": false}],
  "paths": ["/usr/share/lw-test-only-path"],
  "rc_files": []
}
JSON

log3="$home3/sudo.log"
run_all "$home3" "$log3"

for want in "systemctl disable pcscd.socket" \
            "systemctl stop pcscd.socket" \
            "/usr/share/lw-test-only-path"; do
    if grep -q -- "$want" "$log3" 2>/dev/null; then
        pass "paketsiz manifesto: hedeflendi: $want"
    else
        fail "paketsiz manifesto: hedeflenmedi: $want"
    fi
done

if grep -q "pacman" "$log3" 2>/dev/null; then
    fail "paket listesi bosken paket yoneticisi cagrildi."
else
    pass "paket listesi bos: paket yoneticisi cagrilmadi."
fi

if [[ ! -f "$home3/.local/share/legal-workstation/manifest.json" ]]; then
    pass "paketsiz manifesto --all sonrasi silindi."
else
    fail "paketsiz manifesto silinmedi."
fi

# --- Case 4: package manager fails -> best-effort, must still delete manifest ---
home4="$(mktemp -d /tmp/lw-all-failpkg-XXXXXX)"
trap 'rm -rf "$tmp_home" "$home2" "$home3" "$home4"' EXIT
fakebin_fail="$home4/fakebin"; mkdir -p "$fakebin_fail"
cat > "$fakebin_fail/sudo" <<'PY'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${SUDO_LOG:?}"
case "$1" in
    pacman) exit 1 ;;
esac
exit 0
PY
chmod +x "$fakebin_fail/sudo"

mkdir -p "$home4/.local/share/legal-workstation"
cat > "$home4/.local/share/legal-workstation/manifest.json" <<'JSON'
{
  "manifest_version": 1,
  "installed_at": "2026-10-16T00:00:00Z",
  "os_family": "arch",
  "packages_added": ["opensc", "ccid", "pcsc-tools"],
  "services_enabled": [],
  "paths": [],
  "rc_files": []
}
JSON

log4="$home4/sudo.log"
PATH="$fakebin_fail:$PATH" run_all "$home4" "$log4"

if grep -q -- "pacman -Rs --noconfirm opensc ccid pcsc-tools" "$log4" 2>/dev/null; then
    pass "başarisiz paket yoneticisi: paket kaldirma denendi."
else
    fail "başarisiz paket yoneticisi: paket kaldirma denenmedi."
fi

if [[ ! -f "$home4/.local/share/legal-workstation/manifest.json" ]]; then
    pass "paket yoneticisi hata verse de manifesto silindi (best-effort)."
else
    fail "paket yoneticisi hatasi kaldirmayi erken sonlandirdi."
fi

# --- Case 5: paket-sahipli kayitli yol --all'da da korunmali ---
# Guvenli dongu sahiplik kontrolu yapar; uninstall_complete paths dongusu de
# ayni korumayi uygulamali (aksi halde paket dosyalari rm -rf ile silinir).
home5="$(mktemp -d /tmp/lw-all-owned-XXXXXX)"
trap 'rm -rf "$tmp_home" "$home2" "$home3" "$home4" "$home5"' EXIT
fakebin5="$home5/fakebin"; mkdir -p "$fakebin5"
cat > "$fakebin5/sudo" <<'PY'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${SUDO_LOG:?}"
exit 0
PY
cat > "$fakebin5/systemctl" <<'PY'
#!/usr/bin/env bash
exit 0
PY
cat > "$fakebin5/dpkg" <<'PY'
#!/usr/bin/env bash
# dpkg -S <path>: yol bir pakete ait
exit 0
PY
cat > "$fakebin5/apt-get" <<'PY'
#!/usr/bin/env bash
exit 0
PY
chmod +x "$fakebin5"/*
mkdir -p "$home5/.local/share/legal-workstation"
cat > "$home5/.local/share/legal-workstation/manifest.json" <<'JSON'
{
  "manifest_version": 1,
  "installed_at": "2026-10-16T00:00:00Z",
  "os_family": "debian",
  "packages_added": ["uyap-editor"],
  "services_enabled": [],
  "paths": ["/usr/share/java/uyap-editor"],
  "rc_files": []
}
JSON
log5="$home5/sudo.log"
HOME="$home5" XDG_DATA_HOME="$home5/.local/share" SUDO_LOG="$log5" LW_OS_OVERRIDE=debian \
    PATH="$fakebin5:$PATH" bash "$DIR_ROOT/bin/legal-workstation" uninstall --all -y >/dev/null 2>&1 || true
if grep -q 'rm -rf /usr/share/java/uyap-editor' "$log5" 2>/dev/null; then
    fail "paket-sahipli kayitli yol --all'da rm -rf ile silindi (sahiplik korunmadi)."
else
    pass "paket-sahipli kayitli yol --all'da da korundu."
fi

# --- Case 6: apt toplu kaldirmayi reddederse tek tek kaldirmaya dusulmeli ---
# (openjdk-11-jre -> default-jre-headless gibi bagimliliklar toplu remove'u bozar.)
home6="$(mktemp -d /tmp/lw-all-aptfallback-XXXXXX)"
trap 'rm -rf "$tmp_home" "$home2" "$home3" "$home4" "$home5" "$home6"' EXIT
fakebin6="$home6/fakebin"; mkdir -p "$fakebin6"
cat > "$fakebin6/sudo" <<'PY'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${SUDO_LOG:?}"
"$@"
PY
cat > "$fakebin6/systemctl" <<'PY'
#!/usr/bin/env bash
exit 0
PY
# apt-get: toplu (birden fazla paket) remove -> hata; tek paket remove -> basari.
cat > "$fakebin6/apt-get" <<'PY'
#!/usr/bin/env bash
pkgs=(); seen=0
for a in "$@"; do
    if [[ "$a" == "remove" ]]; then seen=1; continue; fi
    if [[ "$seen" == "1" && "$a" != "-y" ]]; then pkgs+=("$a"); fi
done
[[ "${#pkgs[@]}" -gt 1 ]] && exit 100
exit 0
PY
chmod +x "$fakebin6"/*
mkdir -p "$home6/.local/share/legal-workstation"
cat > "$home6/.local/share/legal-workstation/manifest.json" <<'JSON'
{
  "manifest_version": 1,
  "installed_at": "2026-10-16T00:00:00Z",
  "os_family": "debian",
  "packages_added": ["aaa", "bbb", "ccc"],
  "services_enabled": [],
  "paths": [],
  "rc_files": []
}
JSON
log6="$home6/sudo.log"
HOME="$home6" XDG_DATA_HOME="$home6/.local/share" SUDO_LOG="$log6" LW_OS_OVERRIDE=debian \
    PATH="$fakebin6:$PATH" bash "$DIR_ROOT/bin/legal-workstation" uninstall --all -y >/dev/null 2>&1 || true
for p in aaa bbb ccc; do
    if grep -qx "apt-get remove -y $p" "$log6" 2>/dev/null; then
        pass "apt toplu hatasinda tek tek kaldirildi: $p"
    else
        fail "apt toplu hatasinda tek tek kaldirma yok: $p"
    fi
done
if grep -qx "apt-get autoremove -y" "$log6" 2>/dev/null; then
    pass "apt toplu hatasinda orphan temizligi (autoremove) yapildi."
else
    fail "apt toplu hatasinda autoremove calismadi."
fi

echo
if [[ "$failures" -eq 0 ]]; then
    echo "==> [BASARILI] Tam kaldirma testi tamamlandi."
    exit 0
fi
echo "==> [BASARISIZ] $failures kontrol basarisiz oldu."
exit 1
