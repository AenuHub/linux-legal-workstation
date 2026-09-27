#!/usr/bin/env bash
# macOS Legal Workstation - Avukatlar İçin Tek Komutla macOS Kurulum Betiği
# Repository: https://github.com/AenuHub/linux-legal-workstation

set -euo pipefail

DIR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$DIR_ROOT/lib/common.sh"
# shellcheck disable=SC1091
source "$DIR_ROOT/lib/macos.sh"

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

    macos_install_all

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
