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
