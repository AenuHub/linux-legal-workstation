#!/usr/bin/env bash
# Common utilities and helper functions for Legal Workstation

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
    # Test seam: allow overriding detection without a container.
    if [[ -n "${LW_OS_OVERRIDE:-}" ]]; then
        echo "$LW_OS_OVERRIDE"
        return 0
    fi

    if [[ "$(uname -s)" == "Darwin" ]]; then
        echo "macos"
        return 0
    fi

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

# Install PTT UETS E-İmza client
common_install_uets() {
    log_step "PTT UETS (Ulusal Elektronik Tebligat Sistemi) E-İmza İstemcisi kuruluyor..."

    local uets_url="https://api.etebligat.gov.tr/v1/auth/_eimza/uets-eimza.jar"
    local uets_dir="/opt/uets"
    local jar_path="$uets_dir/uets-eimza.jar"
    local icon_path="$uets_dir/uets.png"
    local launcher_path="/usr/local/bin/uets-eimza"
    local desktop_path="/usr/share/applications/uets.desktop"

    require_sudo
    sudo mkdir -p "$uets_dir"

    log_info "Resmi PTT UETS sunucusundan uets-eimza.jar indiriliyor..."
    local tmp_jar
    tmp_jar=$(mktemp /tmp/uets-jar-XXXXXX.jar)

    if curl -sSL -L --connect-timeout 8 --max-time 120 "$uets_url" -o "$tmp_jar"; then
        sudo cp "$tmp_jar" "$jar_path"
        sudo chmod 644 "$jar_path"
        rm -f "$tmp_jar"

        # Extract official icon from jar if unzip is present
        if has_cmd unzip; then
            unzip -p "$jar_path" images/logo.png > /tmp/uets-logo.png 2>/dev/null || true
            if [[ -s /tmp/uets-logo.png ]]; then
                sudo cp /tmp/uets-logo.png "$icon_path"
                sudo chmod 644 "$icon_path"
                rm -f /tmp/uets-logo.png
            fi
        fi

        # Create launcher script
        sudo tee "$launcher_path" > /dev/null << 'EOF'
#!/usr/bin/env bash
# PTT UETS E-İmza Başlatıcı
UETS_JAR="/opt/uets/uets-eimza.jar"

if [[ ! -f "$UETS_JAR" ]]; then
    echo "Hata: PTT UETS istemcisi ($UETS_JAR) bulunamadı." >&2
    exit 1
fi

# Find java runtime
JAVA_BIN="java"
for jpath in \
    "$HOME/.local/share/jvm/temurin-11/bin/java" \
    /usr/lib/jvm/java-11-*/bin/java \
    /usr/lib/jvm/java-8-*/bin/java \
    /usr/lib/jvm/java-1.8.0-openjdk/bin/java \
    /usr/lib/jvm/java-11-openjdk*/bin/java \
    /usr/bin/java; do
    if [[ -x "$jpath" ]]; then
        JAVA_BIN="$jpath"
        break
    fi
done

exec "$JAVA_BIN" -jar "$UETS_JAR" "$@"
EOF
        sudo chmod +x "$launcher_path"

        # Create desktop shortcut
        sudo tee "$desktop_path" > /dev/null << EOF
[Desktop Entry]
Name=PTT UETS E-İmza
GenericName=Elektronik Tebligat İmza İstemcisi
Comment=PTT Ulusal Elektronik Tebligat Sistemi E-İmza Uygulaması
Exec=$launcher_path
Icon=${icon_path}
Terminal=false
Type=Application
Categories=Office;Utility;
Keywords=uets;tebligat;e-tebligat;ptt;e-imza;imza;
EOF
        sudo chmod 644 "$desktop_path"

        # Also copy to user desktop applications if directory exists
        if [[ -d "$HOME/.local/share/applications" ]]; then
            cp "$desktop_path" "$HOME/.local/share/applications/uets.desktop" 2>/dev/null || true
        fi

        log_success "PTT UETS E-İmza İstemcisi kuruldu ($launcher_path)."
    else
        rm -f "$tmp_jar"
        log_warn "PTT UETS istemcisi indirilemedi. İnternet bağlantınızı kontrol edin."
    fi
}

# Ensure AKİA desktop entry with Palma / PIN keywords is present
common_ensure_akia_desktop() {
    log_info "E-İmza Kart & PIN Yönetimi (AKİA / Palma) kısayolu kontrol ediliyor..."
    local desktop_dir="/usr/share/applications"
    local user_desktop_dir="$HOME/.local/share/applications"

    local akia_exec=""
    for cand in /usr/local/bin/akia /usr/bin/akia /opt/Akia/Akia /opt/Akia/akia /opt/akia/bin/akia /opt/akia/akia "$HOME/.local/bin/akia"; do
        if [[ -x "$cand" ]]; then
            akia_exec="$cand"
            break
        fi
    done

    # If binary found but /usr/local/bin/akia does not exist, create symlink
    if [[ -n "$akia_exec" && ! -e /usr/local/bin/akia ]]; then
        require_sudo
        sudo ln -sf "$akia_exec" /usr/local/bin/akia 2>/dev/null || true
    fi

    # Determine icon path
    local akia_icon="akia"
    if [[ -f /opt/Akia/Akia.png ]]; then
        akia_icon="/opt/Akia/Akia.png"
    fi

    if [[ -n "$akia_exec" ]]; then
        local entry_content="[Desktop Entry]
Type=Application
Name=AKİA - E-İmza Kart & PIN Yönetimi
GenericName=Akıllı Kart ve PIN Yönetimi (Palma / Akis)
Comment=TÜBİTAK AKİS / TÜRKTRUST / BaroKart E-İmza PIN Değiştirme ve PUK Blokaj Kaldırma Aracı
Icon=$akia_icon
Exec=$akia_exec
Categories=Utility;Security;
Keywords=akia;palma;akis;pin;puk;blokaj;sertifika;e-imza;kart;turktrust;barokart;
Terminal=false"

        if [[ -d "$desktop_dir" ]]; then
            echo "$entry_content" | sudo tee "$desktop_dir/akia.desktop" > /dev/null 2>&1 || true
        fi
        mkdir -p "$user_desktop_dir"
        echo "$entry_content" > "$user_desktop_dir/akia.desktop" 2>/dev/null || true
        log_success "AKİA (PIN / Blokaj Kaldırma / Palma) masaüstü aramasına entegre edildi."
    fi
}

# Ensure ~/.local/bin (where the legal-workstation CLI is installed) is available
# on the user's PATH for future shell sessions. Idempotent: uses a marker comment
# so repeated installs never append duplicate entries.
ensure_local_bin_on_path() {
    local bin_dir="$HOME/.local/bin"
    local marker="# Added by legal-workstation"
    local export_line="export PATH=\"$bin_dir:\$PATH\""
    local updated_any=false
    local rc

    for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
        [[ -f "$rc" ]] || continue
        updated_any=true
        if grep -qF "$marker" "$rc" 2>/dev/null; then
            continue
        fi
        printf '\n%s\n%s\n' "$marker" "$export_line" >> "$rc"
        log_info "$bin_dir kabuk PATH'ine eklendi: $rc"
        manifest_record_rc "$rc"
    done

    # Minimal environments may have none of the standard rc files.
    if [[ "$updated_any" != true ]]; then
        printf '%s\n%s\n' "$marker" "$export_line" >> "$HOME/.profile"
        log_info "$bin_dir kabuk PATH'ine eklendi: $HOME/.profile"
        manifest_record_rc "$HOME/.profile"
    fi
}

# --- Install manifest (install-time tracking) --------------------------------
# Records what the installer newly added so `uninstall --all` can remove exactly
# those packages/services/paths without touching pre-existing software.

LW_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

manifest_cli() {
    if ! has_cmd python3; then
        log_warn "python3 bulunamadi; kurulum manifestosu kullanilamaz."
        return 1
    fi
    python3 "$LW_LIB_DIR/manifest.py" "$@"
}

# Create/merge the manifest. Uses the detected OS family for the schema record.
manifest_init() {
    LW_OS_FAMILY="$(detect_os)" manifest_cli init || true
}

# Record only packages that are not already present on the system.
manifest_record_new_packages() {
    local missing=() p
    for p in "$@"; do
        if ! pkg_present "$p"; then
            missing+=("$p")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        manifest_cli add-package "${missing[@]}" || true
    fi
}

# Record a service together with its state *before* we enable it.
manifest_record_service_if_new() {
    local unit="$1" was_enabled=0 was_active=0
    if systemctl is-enabled --quiet "$unit" 2>/dev/null; then
        was_enabled=1
    fi
    if systemctl is-active --quiet "$unit" 2>/dev/null; then
        was_active=1
    fi
    manifest_cli add-service "$unit" "$was_enabled" "$was_active" || true
}

manifest_record_rc() {
    if [[ -f "$1" ]]; then
        manifest_cli add-rc "$1" || true
    fi
}

# Is a package already installed on this system?
pkg_present() {
    local pkg="$1"
    case "$(detect_os)" in
        arch)   pacman -Qq "$pkg" >/dev/null 2>&1 ;;
        debian) dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed" ;;
        fedora) rpm -q "$pkg" >/dev/null 2>&1 ;;
        *)      return 1 ;;
    esac
}

# Remove the "# Added by legal-workstation" marker and the PATH export line that
# follows it from the user's shell rc files. Idempotent and safe on any file.
remove_local_bin_from_path() {
    local marker="# Added by legal-workstation"
    local rc tmp
    for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
        [[ -f "$rc" ]] || continue
        if ! grep -qF "$marker" "$rc" 2>/dev/null; then
            continue
        fi
        tmp="$(mktemp)"
        awk -v m="$marker" '
            $0 == m { skip = 1; next }
            skip && /^export PATH=/ { skip = 0; next }
            { skip = 0; print }
        ' "$rc" > "$tmp" && mv "$tmp" "$rc"
    done
}
