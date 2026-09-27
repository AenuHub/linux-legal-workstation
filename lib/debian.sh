#!/usr/bin/env bash
# Debian / Ubuntu installation engine for Linux Legal Workstation (Staged)

DIR_LIB="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck disable=SC1091
source "$DIR_LIB/common.sh"

debian_install_all() {
    log_step "Debian / Ubuntu / Linux Mint kurulumu hazırlanıyor..."
    log_info "Bu modül aktif geliştirme aşamasındadır. Paket ve PCSC bağımlılıkları:"
    log_info " - pcscd, libccid, libpcsclite1, pcsc-tools, opensc, openjdk-11-jre"
    log_warn "Debian motoru tam otomatik testleri tamamlandığında yayınlanacaktır."
    exit 0
}
