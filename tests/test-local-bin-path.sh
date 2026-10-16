#!/usr/bin/env bash
# Legal Workstation - ~/.local/bin PATH entegrasyonu testi (H4)
#
# ensure_local_bin_on_path yardimcisi, mevcut kabuk rc dosyalarina
# ~/.local/bin'i tek seferlik ve tekrarlanabilir (idempotent) sekilde eklemelidir.
set -euo pipefail

DIR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failures=0

pass() { printf '  -> [GECTI] %s\n' "$1"; }
fail() { printf '  [HATA] %s\n' "$1"; failures=$((failures + 1)); }

echo "==> ~/.local/bin PATH yardimcisi test ediliyor..."
tmp_home="$(mktemp -d /tmp/lw-home-XXXXXX)"
trap 'rm -rf "$tmp_home"' EXIT

: > "$tmp_home/.bashrc"
: > "$tmp_home/.zshrc"

# Yardimciyi iki kez cagir: ikinci cagri kopya eklememeli (idempotent).
if ! HOME="$tmp_home" bash -euc "source '$DIR_ROOT/lib/common.sh'; ensure_local_bin_on_path; ensure_local_bin_on_path"; then
    fail "ensure_local_bin_on_path cagrisi hata verdi."
else
    pass "ensure_local_bin_on_path hatasiz calisti."
fi

for rc in .bashrc .zshrc; do
    rcpath="$tmp_home/$rc"
    if ! grep -q '\.local/bin' "$rcpath"; then
        fail "$rc icinde ~/.local/bin PATH kaydi yok."
        continue
    fi
    count="$(grep -c 'Added by legal-workstation' "$rcpath" || true)"
    if [[ "$count" -eq 1 ]]; then
        pass "$rc: tek seferlik, idempotent kayit."
    else
        fail "$rc: beklenen 1 kayit, bulunan $count (idempotent degil)."
    fi
done

echo
if [[ "$failures" -eq 0 ]]; then
    echo "==> [BASARILI] PATH entegrasyon testi tamamlandi."
    exit 0
fi
echo "==> [BASARISIZ] $failures kontrol basarisiz oldu."
exit 1
