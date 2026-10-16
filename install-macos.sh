#!/usr/bin/env bash
# macOS Legal Workstation - Avukatlar İçin Tek Komutla macOS Kurulum Betiği
# Repository: https://github.com/AenuHub/linux-legal-workstation

set -euo pipefail

# --- Bootstrap ---------------------------------------------------------------
# `curl -fsSL .../install-macos.sh | bash` leaves BASH_SOURCE empty and lib/
# unavailable. Re-fetch the repository and re-exec from the extracted copy.
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
    bash "$_bootstrap_dir/install-macos.sh" "$@" || _rc=$?
    rm -rf "$_bootstrap_dir"
    exit "$_rc"
fi

DIR_ROOT="$(cd "$(dirname "$_self")" && pwd)"
# shellcheck disable=SC1091
source "$DIR_ROOT/lib/common.sh"
# shellcheck disable=SC1091
source "$DIR_ROOT/lib/macos.sh"

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
    printf "${CYAN}  Avukatlar İçin Tek Komutla macOS Hukuk Çalışma İstasyonu Kurulumu${NC}\n"
    printf "${BOLD}========================================================================${NC}\n"
    printf "${YELLOW}[BİLGİ] macOS desteği henüz geliştirme ve topluluk testi (Beta) aşamasındadır.${NC}\n\n"
}

main() {
    print_banner

    if [[ "$(uname -s)" != "Darwin" ]]; then
        log_error "Bu kurulum betiği yalnızca macOS (Apple Silicon veya Intel) içindir."
        exit 1
    fi

    local arch
    arch=$(macos_detect_arch)
    log_info "macOS mimarisi tespit edildi: ${BOLD}${arch^^}${NC}"

    [[ "$DRY_RUN" == "1" ]] || macos_install_all

    if [[ "$DRY_RUN" == "1" ]]; then
        log_warn "Kuru çalıştırma (LW_DRY_RUN=1): kurulum adımları atlandı."
        exit 0
    fi

    # Install legal-workstation CLI
    local target_bin="/usr/local/bin"
    if [[ ! -d "$target_bin" ]]; then
        sudo mkdir -p "$target_bin"
    fi
    sudo cp -f "$DIR_ROOT/bin/legal-workstation" "$target_bin/legal-workstation"
    sudo chmod +x "$target_bin/legal-workstation"

    log_step "Kurulum Tamamlandı! Teşhis ve Doğrulama Yapılıyor..."
    "$target_bin/legal-workstation" doctor

    printf "\n${GREEN}${BOLD}Tebrikler! macOS Hukuk Çalışma İstasyonu başarıyla kuruldu.${NC}\n"
    printf "İstediğiniz zaman terminalden ${CYAN}legal-workstation doctor${NC} komutunu çalıştırabilirsiniz.\n\n"
}

main "$@"
