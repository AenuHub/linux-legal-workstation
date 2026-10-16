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
