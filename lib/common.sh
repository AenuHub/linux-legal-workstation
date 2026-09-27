#!/usr/bin/env bash
# Common utilities and helper functions for Linux Legal Workstation

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

log_info() {
    printf "${BLUE}[INFO]${NC} %b\n" "$*"
}

log_success() {
    printf "${GREEN}[BAŞARILI]${NC} %b\n" "$*"
}

log_warn() {
    printf "${YELLOW}[UYARI]${NC} %b\n" "$*"
}

log_error() {
    printf "${RED}[HATA]${NC} %b\n" "$*" >&2
}

log_step() {
    printf "\n${BOLD}${CYAN}==>${NC} ${BOLD}%b${NC}\n" "$*"
}

# Check if command exists
has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

# Detect Distribution
detect_os() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        OS_ID="${ID:-unknown}"
        OS_LIKE="${ID_LIKE:-}"
        OS_NAME="${NAME:-Linux}"
    else
        OS_ID="unknown"
        OS_LIKE=""
        OS_NAME="Linux"
    fi

    case "$OS_ID" in
        arch|omarchy|endeavouros|manjaro|cachyos|garuda)
            echo "arch"
            ;;
        ubuntu|debian|linuxmint|pop)
            echo "debian"
            ;;
        fedora|rhel|centos|rocky|almalinux)
            echo "fedora"
            ;;
        *)
            if [[ "$OS_LIKE" =~ (arch) ]]; then
                echo "arch"
            elif [[ "$OS_LIKE" =~ (debian|ubuntu) ]]; then
                echo "debian"
            elif [[ "$OS_LIKE" =~ (fedora|rhel) ]]; then
                echo "fedora"
            else
                echo "unknown"
            fi
            ;;
    esac
}

# Require sudo privileges (or transparent execution if root)
require_sudo() {
    if [[ $EUID -eq 0 ]]; then
        return 0
    fi

    if has_cmd sudo; then
        if sudo -v; then
            return 0
        else
            log_error "Sudo yetkisi doğrulanamadı. Lütfen yönetici şifrenizi girin."
            exit 1
        fi
    else
        log_error "'sudo' komutu bulunamadı. Lütfen root yetkisiyle veya sudo kurarak çalıştırın."
        exit 1
    fi
}

# Provide transparent sudo fallback for container/root runs
if [[ $EUID -eq 0 ]] && ! has_cmd sudo; then
    sudo() {
        "$@"
    }
fi
