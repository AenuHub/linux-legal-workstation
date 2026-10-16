#!/usr/bin/env bash
# Legal Workstation - Kurulum (bootstrap) duman testi
#
# Guvenlik agi (regresyon korumasi):
#   1. 'BASHASH_SOURCE' gibi yazim hatalari (C1) yakalanir.
#   2. Her lib betigi, kaynak dizininden bagimsiz olarak 'source' edilebilmelidir.
#   3. README'de belgelenen 'curl ... | bash' tek satiri, '_' boru uzerinden
#      calistirildiginda 'unbound variable' ile olmemeli; bootstrap yapip
#      kurulum akisina girmelidir (C2).
set -euo pipefail

DIR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_NAME="$(basename "$DIR_ROOT")"
failures=0

pass() { printf '  -> [GECTI] %s\n' "$1"; }
fail() { printf '  [HATA] %s\n' "$1"; failures=$((failures + 1)); }

echo "==> 1. Statik koruma: yasakli 'BASHASH_SOURCE' yazim hatasi araniyor..."
if grep -rn "BASHASH_SOURCE" "$DIR_ROOT/lib" "$DIR_ROOT"/install.sh "$DIR_ROOT"/install-macos.sh 2>/dev/null; then
    fail "'BASHASH_SOURCE' yazim hatasi bulundu (BASH_SOURCE olmali)."
else
    pass "Yazim hatasi yok."
fi

echo "==> 2. Her lib betigi kaynak dizininden bagimsiz 'source' edilebiliyor mu?"
for lib in "$DIR_ROOT"/lib/*.sh; do
    name="$(basename "$lib")"
    errlog="$(mktemp)"
    if (cd /tmp && bash -euc "source '$lib'") 2>"$errlog"; then
        pass "$name"
    else
        fail "$name source edilemedi:"
        sed 's/^/        /' "$errlog"
    fi
    rm -f "$errlog"
done

echo "==> 3. Boru uzerinden kurulum ('curl ... | bash' taklidi) bootstrap testi..."
tmp_dir="$(mktemp -d /tmp/lw-smoke-XXXXXX)"
trap 'rm -rf "$tmp_dir"' EXIT
tarball="$tmp_dir/repo.tar.gz"
tar --exclude=.git -czf "$tarball" -C "$(dirname "$DIR_ROOT")" "$REPO_NAME"

rc=0
out="$(LW_REPO_TARBALL="file://$tarball" LW_DRY_RUN=1 bash -s < "$DIR_ROOT/install.sh" 2>&1)" || rc=$?

if [[ "$rc" -ne 0 ]]; then
    fail "Boru uzerinden kurulum sifirdan farkli kodla bitti (rc=$rc)."
    printf '%s\n' "$out" | sed 's/^/        /'
elif grep -q "unbound variable" <<<"$out"; then
    fail "'unbound variable' hatasi olustu (BASH_SOURCE bos iken)."
    printf '%s\n' "$out" | sed 's/^/        /'
elif ! grep -q "sistemi alg.land" <<<"$out"; then
    fail "Kurulum bootstrap sonrasi isletim sistemi tespitine ulasmadi."
    printf '%s\n' "$out" | sed 's/^/        /'
else
    pass "Boru uzerinden kurulum bootstrap yapip akisa girdi."
fi

echo "==> 4. lib/common.sh yokken 'uninstall' 'command not found' ile olmemeli..."
fb_home="$(mktemp -d /tmp/lw-nolib-XXXXXX)"
trap 'rm -rf "$tmp_dir" "$fb_home"' EXIT
fb_bin="$fb_home/bin"; mkdir -p "$fb_bin"
cat > "$fb_bin/systemctl" <<'PY'
#!/usr/bin/env bash
exit 0
PY
cat > "$fb_bin/sudo" <<'PY'
#!/usr/bin/env bash
exit 0
PY
chmod +x "$fb_bin"/*
mkdir -p "$fb_home/home/.local/bin"
cp "$DIR_ROOT/bin/legal-workstation" "$fb_home/home/.local/bin/legal-workstation"
fb_out="$fb_home/out.log"
rc=0
HOME="$fb_home/home" XDG_DATA_HOME="$fb_home/home/.local/share" PATH="$fb_bin:$PATH" \
    bash "$fb_home/home/.local/bin/legal-workstation" uninstall -y >"$fb_out" 2>&1 || rc=$?
if [[ "$rc" -eq 0 ]] && ! grep -q "command not found" "$fb_out"; then
    pass "kutuphanesiz CLI: uninstall guvenli sekilde tamamlandi (rc=0)."
else
    fail "kutuphanesiz CLI: uninstall basarisiz (rc=$rc)."
    tail -n 3 "$fb_out" | sed 's/^/        /'
fi

echo
if [[ "$failures" -eq 0 ]]; then
    echo "==> [BASARILI] Bootstrap duman testi tamamlandi."
    exit 0
fi
echo "==> [BASARISIZ] $failures kontrol basarisiz oldu."
exit 1
