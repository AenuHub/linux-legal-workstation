#!/usr/bin/env bash
# Legal Workstation - Avukatlar İçin Kurulum Betiği
# Repository: https://github.com/AenuHub/linux-legal-workstation

set -euo pipefail

DIR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$DIR_ROOT/lib/common.sh"

print_banner() {
    cat << "EOF"
  _      _                      _                     _  __          __        _       _        _   _             
 | |    (_)                    | |                   | | \ \        / /       | |     | |      | | (_)            
 | |     _ _ __  _   ___  __   | |     ___  __ _  __ | |  \ \  /\  / /___  _ __| | _____| |_ __ _| |_ _  ___  _ __  
 | |    | | '_ \| | | \ \/ /   | |    / _ \/ _` |/ _` | |   \ \/  \/ // _ \| '__| |/ / __| __/ _` | __| |/ _ \| '_ \ 
 | |____| | | | | |_| |>  <    | |___|  __/ (_| | (_| | |    \  /\  /| (_) | |  |   <\__ \ || (_| | |_| | (_) | | | |
 |______|_|_| |_|\__,_/_/\_\   |______\___|\__, |\__,_|_|     \/  \/  \___/|_|  |_|\_\___/\__\__,_|\__|_|\___/|_| |_|
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
            arch_install_all
            ;;
        debian)
            # shellcheck disable=SC1091
            source "$DIR_ROOT/lib/debian.sh"
            debian_install_all
            ;;
        fedora)
            # shellcheck disable=SC1091
            source "$DIR_ROOT/lib/fedora.sh"
            fedora_install_all
            ;;
        macos)
            # shellcheck disable=SC1091
            source "$DIR_ROOT/lib/macos.sh"
            macos_install_all
            ;;
        *)
            log_error "Desteklenmeyen veya tanımlanamayan işletim sistemi: $target_os"
            log_warn "Desteklenen sistemler: Arch Linux, Ubuntu/Debian/Mint, Fedora/RHEL, macOS."
            exit 1
            ;;
    esac

    # Install CLI doctor tool to ~/.local/bin
    mkdir -p "$HOME/.local/bin"
    cp -f "$DIR_ROOT/bin/legal-workstation" "$HOME/.local/bin/legal-workstation"
    chmod +x "$HOME/.local/bin/legal-workstation"

    log_step "Kurulum Tamamlandı! Teşhis ve Doğrulama Yapılıyor..."
    "$HOME/.local/bin/legal-workstation" doctor

    printf "\n${GREEN}${BOLD}Tebrikler! Hukuk Çalışma İstasyonu başarıyla kuruldu.${NC}\n"
    printf "İstediğiniz zaman terminalden ${CYAN}legal-workstation doctor${NC} komutunu çalıştırabilirsiniz.\n\n"
}

main "$@"
