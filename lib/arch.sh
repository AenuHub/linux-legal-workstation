#!/usr/bin/env bash
# Arch Linux & Omarchy installation engine for Linux Legal Workstation

# Ensure common helpers are loaded
DIR_LIB="$(cd "$(dirname "${BASHASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck disable=SC1091
source "$DIR_LIB/common.sh"

arch_install_system_packages() {
    log_step "1/5: Akıllı kart ve sistem bağımlılıkları kuruluyor..."
    require_sudo

    local pkgs=(
        pcsclite
        ccid
        opensc
        pcsc-tools
        jre11-openjdk
        libayatana-appindicator3
        curl
        tar
        binutils # for 'ar' utility to unpack deb packages
    )

    log_info "Pacman paketleri kontrol ediliyor: ${pkgs[*]}"
    sudo pacman -S --needed --noconfirm "${pkgs[@]}"

    log_step "2/5: PC/SC Akıllı Kart servisi etkinleştiriliyor..."
    sudo systemctl enable --now pcscd.socket pcscd.service
    log_success "PC/SC Daemon (pcscd) aktif ve çalışıyor."
}

arch_install_uyap_editor() {
    log_step "3/5: UYAP Doküman Editörü yapılandırılıyor..."

    if has_cmd uyap-dokuman || [[ -f /usr/bin/uyap-dokuman || -f "$HOME/.local/bin/uyap-dokuman" ]]; then
        log_info "UYAP Editör zaten kurulu, başlatıcı wrapper kontrol ediliyor..."
    else
        # Check for AUR helpers
        local aur_helper=""
        if has_cmd yay; then
            aur_helper="yay"
        elif has_cmd paru; then
            aur_helper="paru"
        fi

        if [[ -n "$aur_helper" ]]; then
            log_info "AUR yardımcısı ($aur_helper) üzerinden uyap-editor kuruluyor..."
            "$aur_helper" -S --needed --noconfirm uyap-editor
        else
            log_warn "AUR yardımcısı (yay/paru) bulunamadı. Resmi paket doğrudan indiriliyor..."
            # Direct download fallback from official UYAP CDN if no AUR helper
            local tmp_dir
            tmp_dir=$(mktemp -d /tmp/uyap-install-XXXXXX)
            curl -sSL "https://cdn.uyap.gov.tr/editor/uyap-editor.deb" -o "$tmp_dir/uyap.deb" 2>/dev/null || true
            if [[ -f "$tmp_dir/uyap.deb" ]]; then
                require_sudo
                cd "$tmp_dir" && ar x uyap.deb && tar -xf data.tar.* -C /
                rm -rf "$tmp_dir"
            else
                log_warn "Otomatik UYAP Editör paketi çekilemedi. 'yay -S uyap-editor' çalıştırmanız önerilir."
            fi
        fi
    fi

    # Ensure ~/.local/bin wrapper with Java 11 and PKCS11 support
    mkdir -p "$HOME/.local/bin" "$HOME/.local/lib"
    cat << 'EOF' > "$HOME/.local/bin/uyap-dokuman"
#!/bin/bash
# UYAP Editor wrapper for Linux Legal Workstation
export LD_LIBRARY_PATH="$HOME/.local/lib:/usr/lib/pkcs11:${LD_LIBRARY_PATH}"
export UYAP_EDITOR_JAVA="/usr/lib/jvm/java-11-openjdk/bin/java"

if [[ -x /usr/bin/uyap-dokuman ]]; then
    exec /usr/bin/uyap-dokuman "$@"
elif [[ -f /usr/share/java/uyap-editor/editor_lib.jar ]]; then
    exec "$UYAP_EDITOR_JAVA" -Xmx256m \
        -cp '/usr/share/java/uyap-editor/*' \
        tr.com.havelsan.uyap.system.editor.common.WPAppManager \
        getNewWPInstance EDITOR_TYPE_DOCUMENT "$@"
else
    echo "Hata: UYAP Doküman Editörü kütüphaneleri bulunamadı." >&2
    exit 1
fi
EOF
    chmod +x "$HOME/.local/bin/uyap-dokuman"

    # Symlink opensc-pkcs11 for easy discovery
    if [[ -f /usr/lib/opensc-pkcs11.so ]]; then
        ln -sf /usr/lib/opensc-pkcs11.so "$HOME/.local/lib/libopensc-pkcs11.so" 2>/dev/null || true
    fi

    log_success "UYAP Doküman Editörü ve Java 11 çalışma zamanı hazırlandı."
}

arch_install_adalet_eimza() {
    log_step "4/5: Adalet E-İmza Uygulaması (Avukat Portal Girişi) kuruluyor..."

    local target_dir="$HOME/.local/lib/adalet-eimza-tray"
    local bin_dir="$HOME/.local/bin"
    local app_dir="$HOME/.local/share/applications"
    local service_dir="$HOME/.config/systemd/user"

    mkdir -p "$target_dir" "$bin_dir" "$app_dir" "$service_dir" "$HOME/.local/lib"

    # AppIndicator compatibility links
    ln -sf /usr/lib/libayatana-appindicator3.so.1 "$HOME/.local/lib/libappindicator3.so.1" 2>/dev/null || true
    ln -sf /usr/lib/libayatana-appindicator3.so.1 "$HOME/.local/lib/libappindicator3.so" 2>/dev/null || true

    log_info "Resmi UYAP CDN üzerinden en son Adalet E-İmza sürümü sorgulanıyor..."
    local cdn_json_url="https://cdn.uyap.gov.tr/framework/public/latest.json"
    local latest_data
    latest_data=$(curl -sSL --connect-timeout 6 --max-time 15 "$cdn_json_url" 2>/dev/null || true)

    local download_url=""
    local latest_version=""
    if [[ -n "$latest_data" ]] && has_cmd python3; then
        latest_version=$(python3 -c "import json, sys; d=json.loads(sys.argv[1]); print(d['releases']['ubuntu']['latestVersion'])" "$latest_data" 2>/dev/null || true)
        download_url=$(python3 -c "import json, sys; d=json.loads(sys.argv[1]); print(d['releases']['ubuntu']['downloadUrl'])" "$latest_data" 2>/dev/null || true)
    fi

    if [[ -n "$download_url" ]]; then
        log_info "Sürüm: v${latest_version} indiriliyor: $download_url"
        local tmp_dir
        tmp_dir=$(mktemp -d /tmp/eimza-install-XXXXXX)
        curl -sSL --progress-bar "$download_url" -o "$tmp_dir/eimza.deb"

        cd "$tmp_dir"
        ar x eimza.deb
        mkdir -p extract
        tar -xf data.tar.* -C extract

        cp -r extract/usr/lib/adalet-eimza-tray/* "$target_dir/" 2>/dev/null || true
        if [[ -d extract/usr/share/icons ]]; then
            mkdir -p "$HOME/.local/share/icons"
            cp -r extract/usr/share/icons/* "$HOME/.local/share/icons/" 2>/dev/null || true
        fi
        rm -rf "$tmp_dir"
        log_success "Adalet E-İmza Uygulaması v$latest_version kuruldu."
    else
        log_warn "CDN üzerinden otomatik indirme yapılamadı veya internet bağlantısı yok."
    fi

    # Create wrapper binary
    cat << 'EOF' > "$bin_dir/adalet-eimza-tray"
#!/bin/bash
export LD_LIBRARY_PATH="$HOME/.local/lib:${LD_LIBRARY_PATH}"
if [[ -x "$HOME/.local/lib/adalet-eimza-tray/bin/adalet-eimza-tray" ]]; then
    exec "$HOME/.local/lib/adalet-eimza-tray/bin/adalet-eimza-tray" "$@"
fi
EOF
    chmod +x "$bin_dir/adalet-eimza-tray"

    # Install updater script
    cat << 'EOF' > "$bin_dir/check-adalet-eimza-update"
#!/bin/bash
set -euo pipefail
CURRENT_DIR="$HOME/.local/lib/adalet-eimza-tray"
LATEST_JSON_URL="https://cdn.uyap.gov.tr/framework/public/latest.json"

echo "Adalet E-İmza güncelleme kontrolü yapılıyor..."
LATEST_DATA=$(curl -sSL --connect-timeout 5 --max-time 10 "$LATEST_JSON_URL" 2>/dev/null || true)
if [[ -z "$LATEST_DATA" ]]; then
    echo "Uyarı: Adalet E-İmza sunucusuna erişilemedi, atlanıyor."
    exit 0
fi

LATEST_VERSION=$(python3 -c "import json, sys; d=json.loads(sys.argv[1]); print(d['releases']['ubuntu']['latestVersion'])" "$LATEST_DATA" 2>/dev/null || true)
DOWNLOAD_URL=$(python3 -c "import json, sys; d=json.loads(sys.argv[1]); print(d['releases']['ubuntu']['downloadUrl'])" "$LATEST_DATA" 2>/dev/null || true)

if [[ -z "$LATEST_VERSION" || -z "$DOWNLOAD_URL" ]]; then
    exit 0
fi

CURRENT_JAR=$(ls "$CURRENT_DIR/lib/app/eimza-tray-"*.jar 2>/dev/null | head -n 1 || true)
CURRENT_VERSION=""
if [[ -n "$CURRENT_JAR" ]]; then
    CURRENT_VERSION=$(basename "$CURRENT_JAR" | sed -E 's/eimza-tray-(.*)\.jar/\1/')
fi

if [[ -n "$CURRENT_VERSION" && "$CURRENT_VERSION" == "$LATEST_VERSION" ]]; then
    echo "Adalet E-İmza zaten güncel (v$CURRENT_VERSION)."
    exit 0
fi

echo "Yeni sürüm bulundu: v$LATEST_VERSION (Mevcut: v${CURRENT_VERSION:-yok})"
TMP_DIR=$(mktemp -d /tmp/eimza-update-XXXXXX)
trap 'rm -rf "$TMP_DIR"' EXIT

curl -sSL "$DOWNLOAD_URL" -o "$TMP_DIR/eimza.deb"
cd "$TMP_DIR"
ar x eimza.deb
mkdir -p extract
tar -xf data.tar.* -C extract
cp -r extract/usr/lib/adalet-eimza-tray/* "$CURRENT_DIR/"
systemctl --user restart adalet-eimza-tray.service 2>/dev/null || true
echo "Adalet E-İmza v$LATEST_VERSION sürümüne güncellendi!"
EOF
    chmod +x "$bin_dir/check-adalet-eimza-update"

    # Install systemd user service
    cat << EOF > "$service_dir/adalet-eimza-tray.service"
[Unit]
Description=Adalet E-Imza Tray Uygulamasi
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
Environment=LD_LIBRARY_PATH=$HOME/.local/lib
ExecStart=$HOME/.local/bin/adalet-eimza-tray
Restart=on-failure
RestartSec=10
SuccessExitStatus=143

[Install]
WantedBy=default.target
EOF

    # Install desktop entry
    cat << EOF > "$app_dir/tr.gov.adalet.eimza-tray.desktop"
[Desktop Entry]
Name=Adalet E-İmza
Comment=Adalet Bakanlığı E-İmza Entegrasyon Servisi (Avukat Portal)
Exec=$bin_dir/adalet-eimza-tray
Icon=adalet-eimza-tray
Terminal=false
Type=Application
Categories=Utility;Office;
StartupNotify=false
EOF

    # Enable and start user service
    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable --now adalet-eimza-tray.service 2>/dev/null || true
    log_success "Adalet E-İmza kullanıcı servisi etkinleştirildi ve başlatıldı."
}

arch_install_akia() {
    log_step "TÜBİTAK AKİS / AKİA (libakisp11.so) akıllı kart aracı kuruluyor..."

    if has_cmd akia || [[ -f /usr/local/bin/akia || -f /opt/Akia/Akia || -f /opt/Akia/akia || -f "$HOME/.local/bin/akia" ]]; then
        log_info "AKİA uygulaması sistemde mevcut."
    else
        local aur_helper=""
        if has_cmd yay; then
            aur_helper="yay"
        elif has_cmd paru; then
            aur_helper="paru"
        fi

        if [[ -n "$aur_helper" ]]; then
            log_info "AUR yardımcısı ($aur_helper) üzerinden akia kuruluyor..."
            "$aur_helper" -S --needed --noconfirm akia 2>/dev/null || true
        fi

        if ! has_cmd akia && [[ ! -f /opt/Akia/Akia && ! -f /opt/Akia/akia ]]; then
            log_info "Resmi TÜBİTAK paketinden AKİS / AKİA doğrudan kuruluyor..."
            local akia_zip_url="https://akiskart.bilgem.tubitak.gov.tr/wp-content/uploads/sites/33/2026/06/Akia_linux_6_8_10.deb_.zip"
            local tmp_dir
            tmp_dir=$(mktemp -d /tmp/akia-arch-XXXXXX)

            if curl -sSL -L --connect-timeout 8 --max-time 180 "$akia_zip_url" -o "$tmp_dir/akia.zip"; then
                cd "$tmp_dir"
                unzip -q akia.zip
                local deb_file
                deb_file=$(find . -name "*.deb" | head -n 1)
                if [[ -n "$deb_file" && -f "$deb_file" ]]; then
                    require_sudo
                    ar x "$deb_file"
                    mkdir -p extract
                    tar -xf data.tar.* -C extract
                    if [[ -d extract/opt/Akia ]]; then
                        sudo cp -r extract/opt/Akia /opt/
                        if [[ -f extract/opt/Akia/Akia ]]; then
                            sudo ln -sf /opt/Akia/Akia /usr/local/bin/akia 2>/dev/null || true
                        else
                            sudo ln -sf /opt/Akia/akia /usr/local/bin/akia 2>/dev/null || true
                        fi
                        sudo ln -sf /opt/Akia/libakisp11.so /usr/lib/libakisp11.so 2>/dev/null || true
                    fi
                fi
                cd "$DIR_LIB/.." && rm -rf "$tmp_dir"
            else
                rm -rf "$tmp_dir"
            fi
        fi
    fi

    # Symlink to user local lib if present
    mkdir -p "$HOME/.local/lib"
    if [[ -f /usr/lib/libakisp11.so ]]; then
        ln -sf /usr/lib/libakisp11.so "$HOME/.local/lib/libakisp11.so" 2>/dev/null || true
    elif [[ -f /opt/Akia/libakisp11.so ]]; then
        ln -sf /opt/Akia/libakisp11.so "$HOME/.local/lib/libakisp11.so" 2>/dev/null || true
    fi
}

arch_install_all() {
    arch_install_system_packages
    arch_install_akia
    arch_install_uyap_editor
    arch_install_adalet_eimza
    common_install_uets
    common_ensure_akia_desktop
}

