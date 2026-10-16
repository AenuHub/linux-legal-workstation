#!/usr/bin/env bash
# Legal Workstation - Avukatlar İçin Kurulum Betiği
# Repository: https://github.com/AenuHub/linux-legal-workstation

set -euo pipefail

# --- Bootstrap ---------------------------------------------------------------
# The documented one-liner is `curl -fsSL .../install.sh | bash`. In that mode
# there is no script file on disk and no `lib/` alongside it, so BASH_SOURCE is
# empty. Re-fetch the repository into a temp dir and re-exec ourselves from there.
_self="${BASH_SOURCE[0]:-}"
if [[ -z "$_self" || ! -f "$_self" ]]; then
    : "${LW_REPO_TARBALL:=https://github.com/AenuHub/linux-legal-workstation/archive/refs/heads/main.tar.gz}"
    _bootstrap_dir="$(mktemp -d "${TMPDIR:-/tmp}/legal-workstation-XXXXXX")"
    printf '[*] Kurulum deposu indiriliyor...\n'
    if ! curl -fsSL "$LW_REPO_TARBALL" | tar -xz -C "$_bootstrap_dir" --strip-components=1; then
        printf '[HATA] Kurulum deposu indirilemedi: %s\n' "$LW_REPO_TARBALL" >&2
        exit 1
    fi
    _rc=0
    bash "$_bootstrap_dir/install.sh" "$@" || _rc=$?
    rm -rf "$_bootstrap_dir"
    exit "$_rc"
fi

DIR_ROOT="$(cd "$(dirname "$_self")" && pwd)"
# shellcheck disable=SC1091
source "$DIR_ROOT/lib/common.sh"

DRY_RUN="${LW_DRY_RUN:-0}"

print_banner() {
    cat << "EOF"
  _                      _  __          __        _        _        _   _             
 | |                    | | \ \        / /       | |      | |      | | (_)            
 | |     ___  __ _  __ _| |  \ \  /\  / /___  _ _| | _____| |_ __ _| |_ _  ___  _ __  
 | |    / _ \/ _` |/ _` | |   \ \/  \/ // _ \| '__| |/ / __| __/ _` | __| |/ _ \| '_ \ 
 | |___|  __/ (_| | (_| | |    \  /\  /| (_) | |  |   <\__ \ || (_| | |_| | (_) | | | |
 |______\___|\__, |\__,_|_|     \/  \/  \___/|_|  |_|\_\___/\__\__,_|\__|_|\___/|_| |_|
              __/ |                                                                   
             |___/                                                                    
EOF
    printf "${BOLD}========================================================================${NC}\n"
    printf "${CYAN}  Avukatlar İçin Tek Komutla Hukuk Çalışma İstasyonu Kurulumu${NC}\n"
    printf "${BOLD}========================================================================${NC}\n\n"
}

main() {
    print_banner

    local target_os
    target_os=$(detect_os)

    log_info "İşletim sistemi algılandı: ${BOLD}${target_os^^}${NC}"

    case "$target_os" in
        arch)
            # shellcheck disable=SC1091
            source "$DIR_ROOT/lib/arch.sh"
            [[ "$DRY_RUN" == "1" ]] || arch_install_all
            ;;
        debian)
            # shellcheck disable=SC1091
            source "$DIR_ROOT/lib/debian.sh"
            [[ "$DRY_RUN" == "1" ]] || debian_install_all
            ;;
        fedora)
            # shellcheck disable=SC1091
            source "$DIR_ROOT/lib/fedora.sh"
            [[ "$DRY_RUN" == "1" ]] || fedora_install_all
            ;;
        macos)
            # shellcheck disable=SC1091
            source "$DIR_ROOT/lib/macos.sh"
            [[ "$DRY_RUN" == "1" ]] || macos_install_all
            ;;
        *)
            log_error "Desteklenmeyen veya tanımlanamayan işletim sistemi: $target_os"
            log_warn "Desteklenen sistemler: Arch Linux, Ubuntu/Debian/Mint, Fedora/RHEL, macOS."
            exit 1
            ;;
    esac

    if [[ "$DRY_RUN" == "1" ]]; then
        log_warn "Kuru çalıştırma (LW_DRY_RUN=1): kurulum adımları atlandı."
        exit 0
    fi

    # Install CLI doctor tool to ~/.local/bin and make it reachable from PATH
    mkdir -p "$HOME/.local/bin"
    cp -f "$DIR_ROOT/bin/legal-workstation" "$HOME/.local/bin/legal-workstation"
    chmod +x "$HOME/.local/bin/legal-workstation"
    ensure_local_bin_on_path

    log_step "Kurulum Tamamlandı! Teşhis ve Doğrulama Yapılıyor..."
    "$HOME/.local/bin/legal-workstation" doctor

    printf "\n${GREEN}${BOLD}Tebrikler! Hukuk Çalışma İstasyonu başarıyla kuruldu.${NC}\n"
    printf "İstediğiniz zaman terminalden ${CYAN}legal-workstation doctor${NC} komutunu çalıştırabilirsiniz.\n\n"
}

main "$@"
