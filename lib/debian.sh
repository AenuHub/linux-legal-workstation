#!/usr/bin/env bash
# Debian / Ubuntu / Linux Mint installation engine for Legal Workstation
# Supported: Ubuntu 20.04+, 22.04+, 24.04+, Debian 11/12+, Linux Mint 20/21+

DIR_LIB="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck disable=SC1091
source "$DIR_LIB/common.sh"

debian_install_system_packages() {
    log_step "1/4: Debian/Ubuntu akıllı kart ve sistem paketleri kuruluyor..."
    require_sudo

    local pkgs=(
        pcscd
        libccid
        libpcsclite1
        pcsc-tools
        opensc
        openjdk-11-jre
        curl
        unzip
        tar
        binutils
        python3
        xz-utils
    )

    log_info "Apt paket listesi güncelleniyor..."
    sudo apt-get update -qq

    # Check for libayatana-appindicator3-1 or libappindicator3-1
    if apt-cache show libayatana-appindicator3-1 >/dev/null 2>&1; then
        pkgs+=(libayatana-appindicator3-1)
    elif apt-cache show libappindicator3-1 >/dev/null 2>&1; then
        pkgs+=(libappindicator3-1)
    fi

    log_info "Gerekli paketler kuruluyor: ${pkgs[*]}"
    export DEBIAN_FRONTEND=noninteractive
    sudo apt-get install -y -qq "${pkgs[@]}"

    log_step "2/4: PC/SC Akıllı Kart servisi etkinleştiriliyor..."
    if has_cmd systemctl; then
        sudo systemctl enable --now pcscd.socket pcscd.service 2>/dev/null || true
    fi
    if ! (systemctl is-active --quiet pcscd.socket 2>/dev/null) && has_cmd service; then
        sudo service pcscd start 2>/dev/null || true
    fi
    log_success "PC/SC Daemon (pcscd) yapılandırıldı."
}

debian_install_akia() {
    log_step "TÜBİTAK AKİS / AKİA (libakisp11.so) akıllı kart sürücüsü kuruluyor..."
    
    if [[ -f /usr/lib/libakisp11.so || -f /opt/Akia/libakisp11.so ]]; then
        log_info "TÜBİTAK AKİS kütüphanesi sistemde mevcut."
    else
        local akia_zip_url="https://akiskart.bilgem.tubitak.gov.tr/wp-content/uploads/sites/33/2026/06/Akia_linux_6_8_10.deb_.zip"
        local tmp_dir
        tmp_dir=$(mktemp -d /tmp/akia-debian-XXXXXX)

        log_info "Resmi TÜBİTAK sunucusundan AKİS / AKİA sürücüsü indiriliyor..."
        if curl -sSL -L --connect-timeout 8 --max-time 180 "$akia_zip_url" -o "$tmp_dir/akia.zip"; then
            cd "$tmp_dir"
            unzip -q akia.zip
            local deb_file
            deb_file=$(find . -name "*.deb" | head -n 1)
            if [[ -n "$deb_file" && -f "$deb_file" ]]; then
                require_sudo
                sudo apt-get install -y "$deb_file" 2>/dev/null || (sudo dpkg -i "$deb_file" && sudo apt-get install -f -y -qq) || true
                log_success "TÜBİTAK AKİS (libakisp11.so) ve AKİA başarıyla kuruldu."
            fi
            cd "$DIR_LIB/.." && rm -rf "$tmp_dir"
        else
            log_warn "TÜBİTAK AKİS sürücüsü indirilemedi, OpenSC sürücüleri kullanılacak."
            cd "$DIR_LIB/.." && rm -rf "$tmp_dir"
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

debian_install_uyap_editor() {
    log_step "3/5: UYAP Doküman Editörü (.deb) kuruluyor..."

    if has_cmd uyap-dokuman || [[ -f /usr/bin/uyap-dokuman || -f "$HOME/.local/bin/uyap-dokuman" ]]; then
        log_info "UYAP Doküman Editörü sistemde mevcut, başlatıcı kontrol ediliyor..."
    else
        local tmp_dir
        tmp_dir=$(mktemp -d /tmp/uyap-debian-XXXXXX)

        log_info "Resmi UYAP sunucusundan son sürüm indiriliyor..."
        local zip_url="https://rayp.adalet.gov.tr/resimler/2/dosya/uyapeditor_5.4.20_amd64.zip"
        
        if curl -sSL -L --connect-timeout 8 --max-time 120 "$zip_url" -o "$tmp_dir/uyap.zip"; then
            cd "$tmp_dir"
            unzip -q uyap.zip
            local deb_file
            deb_file=$(find . -name "*uyapeditor*.deb" -o -name "*uyap*.deb" | head -n 1)

            if [[ -n "$deb_file" && -f "$deb_file" ]]; then
                log_info "Debian paketi kuruluyor ($deb_file)..."
                require_sudo
                sudo apt-get install -y "$deb_file" 2>/dev/null || (sudo dpkg -i "$deb_file" && sudo apt-get install -f -y -qq) || true
                log_success "UYAP Doküman Editörü başarıyla kuruldu."
            else
                log_warn "Zip arşivinde .deb paketi bulunamadı."
            fi
        else
            log_warn "UYAP Editör zip arşivi indirilemedi. Lütfen internet bağlantınızı kontrol edin."
        fi
        cd "$DIR_LIB/.." && rm -rf "$tmp_dir"
    fi

    # Set up user-level wrapper for Java 11 guarantee
    mkdir -p "$HOME/.local/bin" "$HOME/.local/lib"
    cat << 'EOF' > "$HOME/.local/bin/uyap-dokuman"
#!/bin/bash
# UYAP Editor wrapper for Linux Legal Workstation (Debian/Ubuntu)
export LD_LIBRARY_PATH="$HOME/.local/lib:/opt/Akia:/usr/lib:/usr/lib/x86_64-linux-gnu/pkcs11:/usr/lib/pkcs11:${LD_LIBRARY_PATH}"

# Find Java 11 or 8 runtime
for jcandidate in \
    /usr/lib/jvm/java-11-openjdk-amd64/bin/java \
    /usr/lib/jvm/java-11-openjdk/bin/java \
    /usr/lib/jvm/java-8-openjdk-amd64/jre/bin/java \
    /usr/bin/java
do
    if [[ -x "$jcandidate" ]]; then
        export UYAP_EDITOR_JAVA="$jcandidate"
        break
    fi
done

if [[ -x /usr/bin/uyap-dokuman ]]; then
    exec /usr/bin/uyap-dokuman "$@"
elif [[ -f /usr/share/java/uyap-editor/editor_lib.jar || -f /usr/share/UYAPEditor/editor_lib.jar ]]; then
    _CP="/usr/share/java/uyap-editor/*:/usr/share/UYAPEditor/*"
    exec "${UYAP_EDITOR_JAVA:-java}" -Xmx256m -cp "$_CP" \
        tr.com.havelsan.uyap.system.editor.common.WPAppManager \
        getNewWPInstance EDITOR_TYPE_DOCUMENT "$@"
fi
EOF
    chmod +x "$HOME/.local/bin/uyap-dokuman"

    # Link opensc-pkcs11 to user lib if present
    for p11 in /usr/lib/x86_64-linux-gnu/opensc-pkcs11.so /usr/lib/opensc-pkcs11.so /usr/lib/x86_64-linux-gnu/pkcs11/opensc-pkcs11.so; do
        if [[ -f "$p11" ]]; then
            ln -sf "$p11" "$HOME/.local/lib/libopensc-pkcs11.so" 2>/dev/null || true
            break
        fi
    done

    log_success "UYAP Doküman Editörü başlatıcıları ve kütüphane yolları hazırlandı."
}

debian_install_adalet_eimza() {
    log_step "4/4: Adalet E-İmza Uygulaması (Avukat Portal Girişi) kuruluyor..."

    local target_dir="$HOME/.local/lib/adalet-eimza-tray"
    local bin_dir="$HOME/.local/bin"
    local app_dir="$HOME/.local/share/applications"
    local service_dir="$HOME/.config/systemd/user"

    mkdir -p "$target_dir" "$bin_dir" "$app_dir" "$service_dir" "$HOME/.local/lib"

    # Symlink AppIndicator compatibility for Debian/Ubuntu
    for appind in /usr/lib/x86_64-linux-gnu/libayatana-appindicator3.so.1 /usr/lib/x86_64-linux-gnu/libappindicator3.so.1 /usr/lib/libayatana-appindicator3.so.1; do
        if [[ -f "$appind" ]]; then
            ln -sf "$appind" "$HOME/.local/lib/libappindicator3.so.1" 2>/dev/null || true
            ln -sf "$appind" "$HOME/.local/lib/libappindicator3.so" 2>/dev/null || true
            break
        fi
    done

    log_info "Resmi UYAP CDN üzerinden son Adalet E-İmza sürümü sorgulanıyor..."
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
        tmp_dir=$(mktemp -d /tmp/eimza-deb-install-XXXXXX)
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
        cd "$DIR_LIB/.." && rm -rf "$tmp_dir"
        log_success "Adalet E-İmza Uygulaması v$latest_version kuruldu."
    else
        log_warn "CDN üzerinden otomatik indirme yapılamadı."
    fi

    # Launcher wrapper
    cat << 'EOF' > "$bin_dir/adalet-eimza-tray"
#!/bin/bash
export LD_LIBRARY_PATH="$HOME/.local/lib:/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH}"
if [[ -x "$HOME/.local/lib/adalet-eimza-tray/bin/adalet-eimza-tray" ]]; then
    exec "$HOME/.local/lib/adalet-eimza-tray/bin/adalet-eimza-tray" "$@"
fi
EOF
    chmod +x "$bin_dir/adalet-eimza-tray"

    # Auto-updater script
    cat << 'EOF' > "$bin_dir/check-adalet-eimza-update"
#!/bin/bash
set -euo pipefail
CURRENT_DIR="$HOME/.local/lib/adalet-eimza-tray"
LATEST_JSON_URL="https://cdn.uyap.gov.tr/framework/public/latest.json"

LATEST_DATA=$(curl -sSL --connect-timeout 5 --max-time 10 "$LATEST_JSON_URL" 2>/dev/null || true)
if [[ -z "$LATEST_DATA" ]]; then
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
    exit 0
fi

echo "Yeni Adalet E-İmza sürümü bulundu: v$LATEST_VERSION (Mevcut: v${CURRENT_VERSION:-yok})"
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

    # Systemd user service
    cat << EOF > "$service_dir/adalet-eimza-tray.service"
[Unit]
Description=Adalet E-Imza Tray Uygulamasi
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
Environment=LD_LIBRARY_PATH=$HOME/.local/lib:/usr/lib/x86_64-linux-gnu
ExecStart=$HOME/.local/bin/adalet-eimza-tray
Restart=on-failure
RestartSec=10
SuccessExitStatus=143

[Install]
WantedBy=default.target
EOF

    # Desktop entry
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

    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable --now adalet-eimza-tray.service 2>/dev/null || true
    log_success "Adalet E-İmza servisi Debian/Ubuntu için etkinleştirildi."
}

debian_install_all() {
    debian_install_system_packages
    debian_install_akia
    debian_install_uyap_editor
    debian_install_adalet_eimza
    common_install_uets
    common_ensure_akia_desktop
}

