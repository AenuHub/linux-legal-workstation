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

# Yeniden kurulum senaryosu: ilk kurulumda servis KAPALIYDI (0/0) ve biz actik.
# Ikinci kurulumda servis artik ACIK gorunur (1/1) ama taban cizgisi (0/0)
# KORUNMALIDIR; aksi halde uninstall --all servisi geri almaz.
manifest_cli add-service pcscd.socket 0 0
manifest_cli add-service pcscd.socket 1 1
svc="$(manifest_cli list-services)"
if [[ "$svc" == $'pcscd.socket\t0\t0' ]]; then
    pass "servis taban cizgisi yeniden kayitta korunuyor (0/0)."
else
    fail "servis taban cizgisi bozuldu: '$svc'"
fi

# Zaten acik olan bir servis (bastan 1/1) 1/1 kalmali.
manifest_cli add-service pcscd.service 1 1
manifest_cli add-service pcscd.service 1 1
if grep -q $'^pcscd.service\t1\t1$' <<<"$(manifest_cli list-services)"; then
    pass "onceden acik servis 1/1 olarak korunuyor."
else
    fail "onceden acik servis yanlis kaydedildi."
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

# python3 tam kaldirmada silinmis olabilir; dosya bash ile de temizlenebilmeli.
manifest_init
if [[ -f "$manifest_file" ]]; then
    ( manifest_purge_file ) 2>/dev/null || true
    if [[ ! -f "$manifest_file" ]]; then
        pass "manifest_purge_file python3'ten bagimsiz temizledi."
    else
        fail "manifest_purge_file manifesti temizlemedi."
    fi
else
    fail "manifest yeniden olusturulamadi."
fi

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

# Motor kaydi: distro motorlari yalnizca kendi kurduklari paketleri ve servis
# etkinlestirme ONCESI durumu manifestoya yazmali.
engine_bin="$tmp_home/enginebin"; mkdir -p "$engine_bin"
export ENGINE_STATE="$tmp_home/engine-state"
cat > "$engine_bin/systemctl" <<'PY'
#!/usr/bin/env bash
# Servis "enable --now" cagrilana kadar pasif sayilir.
case "$1" in
    is-enabled) [[ -f "$ENGINE_STATE/enabled" ]] && exit 0; exit 1 ;;
    is-active)  [[ -f "$ENGINE_STATE/active" ]] && exit 0; exit 1 ;;
    enable)     mkdir -p "$ENGINE_STATE"; : > "$ENGINE_STATE/enabled"; : > "$ENGINE_STATE/active"; exit 0 ;;
esac
exit 0
PY
cat > "$engine_bin/pacman" <<'PY'
#!/usr/bin/env bash
exit 1   # hicbir paket kurulu degil
PY
cat > "$engine_bin/apt-cache" <<'PY'
#!/usr/bin/env bash
exit 1
PY
cat > "$engine_bin/apt-get" <<'PY'
#!/usr/bin/env bash
exit 0
PY
cat > "$engine_bin/dnf" <<'PY'
#!/usr/bin/env bash
exit 1
PY
# pkg_present probes: debian -> dpkg-query, fedora -> rpm. Stub both so the
# presence check is deterministic regardless of the host's installed packages.
cat > "$engine_bin/dpkg-query" <<'PY'
#!/usr/bin/env bash
exit 1   # hicbir paket kurulu degil
PY
cat > "$engine_bin/rpm" <<'PY'
#!/usr/bin/env bash
exit 1   # hicbir paket kurulu degil
PY
chmod +x "$engine_bin"/*
export PATH="$engine_bin:$PATH"
# Fedora motoru java-11-openjdk bulamazsa Temurin indirmesin diye sahte JRE.
mkdir -p "$HOME/.local/share/jvm/temurin-11/bin"
: > "$HOME/.local/share/jvm/temurin-11/bin/java"
chmod +x "$HOME/.local/share/jvm/temurin-11/bin/java"

engine_record_check() {
    local lib="$1" fn="$2" os="$3" svc
    manifest_cli delete
    rm -rf "$ENGINE_STATE"
    if ! (
        export LW_OS_OVERRIDE="$os"
        # shellcheck disable=SC1090
        source "$DIR_ROOT/lib/$lib"
        require_sudo() { :; }
        sudo() { "$@"; }
        "$fn"
    ) >/dev/null 2>&1; then
        fail "$os motoru calistirilamadi."
        return
    fi

    if grep -qx "opensc" <<<"$(manifest_cli list-packages)"; then
        pass "$os motoru yeni paketi manifestoya kaydetti."
    else
        fail "$os motoru yeni paketi kaydetmedi: '$(manifest_cli list-packages | tr '\n' ' ')'"
    fi

    svc="$(manifest_cli list-services)"
    if grep -q $'^pcscd.socket\t0\t0$' <<<"$svc" && grep -q $'^pcscd.service\t0\t0$' <<<"$svc"; then
        pass "$os motoru pcscd.socket ve pcscd.service servislerini kaydetti."
    else
        fail "$os motoru servis durumunu yanlis kaydetti: '$svc'"
    fi
}

engine_record_check arch.sh arch_install_system_packages arch
engine_record_check debian.sh debian_install_system_packages debian
engine_record_check fedora.sh fedora_install_system_packages fedora

# Yerel .deb kurulumu: paket adi manifestoya kaydedilmeli (FIX 2).
# debian_install_akia'yi sahte indirme/unzip/dpkg araclariyla sureriz.
deb_bin="$tmp_home/debbin"; mkdir -p "$deb_bin"
cat > "$deb_bin/curl" <<'PY'
#!/usr/bin/env bash
# -o <file>: sahte zip govdesi yaz
out=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) out="$2"; shift 2 ;;
        *) shift ;;
    esac
done
[[ -n "$out" ]] && printf 'zip' > "$out"
exit 0
PY
cat > "$deb_bin/unzip" <<'PY'
#!/usr/bin/env bash
: > "${PWD}/akia_6_8_10_amd64.deb"
exit 0
PY
cat > "$deb_bin/dpkg-deb" <<'PY'
#!/usr/bin/env bash
echo "akia"
exit 0
PY
cat > "$deb_bin/dpkg-query" <<'PY'
#!/usr/bin/env bash
exit 1   # paket onceden kurulu degil
PY
cat > "$deb_bin/sudo" <<'PY'
#!/usr/bin/env bash
exit 0
PY
chmod +x "$deb_bin"/*

manifest_cli delete
PATH="$deb_bin:$PATH" LW_OS_OVERRIDE=debian bash -c '
    set -euo pipefail
    source "$1/lib/debian.sh"
    require_sudo() { :; }
    debian_install_akia
' _ "$DIR_ROOT" >/dev/null 2>&1 || true

if grep -qx "akia" <<< "$(manifest_cli list-packages)"; then
    pass "yerel deb paketi (akia) manifestoya kaydedildi."
else
    fail "yerel deb paketi kaydedilmedi: '$(manifest_cli list-packages | tr '\n' ' ')'"
fi

echo
if [[ "$failures" -eq 0 ]]; then
    echo "==> [BASARILI] Manifesto testi tamamlandi."
    exit 0
fi
echo "==> [BASARISIZ] $failures kontrol basarisiz oldu."
exit 1
