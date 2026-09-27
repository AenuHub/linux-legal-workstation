#!/usr/bin/env bash
# Fedora / Red Hat / CentOS installation engine for Linux Legal Workstation
# Supported: Fedora 38+, 39+, 40+, 41+, 42+, RHEL 9+, Rocky / AlmaLinux

DIR_LIB="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck disable=SC1091
source "$DIR_LIB/common.sh"

fedora_install_system_packages() {
    log_step "1/5: Fedora akıllı kart ve sistem paketleri kuruluyor..."
    require_sudo

    local pkgs=(
        pcsc-lite
        pcsc-lite-ccid
        pcsc-tools
        opensc
        curl
        unzip
        tar
        python3
        binutils
    )

    log_info "Paketler kontrol ediliyor: ${pkgs[*]}"
    sudo dnf install -y "${pkgs[@]}"

    # Optional UI indicator
    if sudo dnf list libayatana-appindicator-gtk3 >/dev/null 2>&1; then
        sudo dnf install -y libayatana-appindicator-gtk3 2>/dev/null || true
    fi

    # Java 11 check: try native dnf package or fallback to isolated Temurin 11 JRE
    if sudo dnf list java-11-openjdk >/dev/null 2>&1; then
        log_info "Fedora depolarından Java 11 OpenJDK kuruluyor..."
        sudo dnf install -y java-11-openjdk
    else
        log_info "İzole Eclipse Temurin Java 11 JRE ortamı hazırlanıyor..."
        local jvm_dir="$HOME/.local/share/jvm/temurin-11"
        if [[ ! -x "$jvm_dir/bin/java" ]]; then
            mkdir -p "$jvm_dir"
            local tmp_jre
            tmp_jre=$(mktemp -d /tmp/temurin-XXXXXX)
            curl -sSL -L "https://api.adoptium.net/v3/binary/latest/11/ga/linux/x64/jre/hotspot/normal/eclipse" -o "$tmp_jre/jre.tar.gz"
            tar -xzf "$tmp_jre/jre.tar.gz" -C "$jvm_dir" --strip-components=1
            rm -rf "$tmp_jre"
        fi
        log_success "Temurin Java 11 JRE başarıyla hazırlandı."
    fi

    log_step "2/5: PC/SC Akıllı Kart servisi etkinleştiriliyor..."
    if has_cmd systemctl; then
        sudo systemctl enable --now pcscd.socket pcscd.service 2>/dev/null || true
    fi
    log_success "PC/SC Daemon (pcscd) yapılandırıldı."
}

fedora_install_akia() {
    log_step "TÜBİTAK AKİS / AKİA (libakisp11.so) akıllı kart sürücüsü kuruluyor..."

    if [[ -f /usr/lib64/libakisp11.so || -f /usr/lib/libakisp11.so || -f /opt/Akia/libakisp11.so ]]; then
        log_info "TÜBİTAK AKİS kütüphanesi sistemde mevcut."
    else
        local akia_rpm_url="https://akiskart.bilgem.tubitak.gov.tr/wp-content/uploads/sites/33/2026/06/Akia_linux_6_8_10.rpm_.zip"
        local tmp_dir
        tmp_dir=$(mktemp -d /tmp/akia-fedora-XXXXXX)

        log_info "Resmi TÜBİTAK sunucusundan AKİS / AKİA RPM paketi indiriliyor..."
        if curl -sSL -L --connect-timeout 8 --max-time 180 "$akia_rpm_url" -o "$tmp_dir/akia.zip"; then
            cd "$tmp_dir"
            unzip -q akia.zip
            local rpm_file
            rpm_file=$(find . -name "*.rpm" | head -n 1)
            if [[ -n "$rpm_file" && -f "$rpm_file" ]]; then
                require_sudo
                sudo dnf install -y "$rpm_file" 2>/dev/null || sudo rpm -Uvh --nodeps "$rpm_file" 2>/dev/null || true
                log_success "TÜBİTAK AKİS (libakisp11.so) ve AKİA başarıyla kuruldu."
            fi
            cd "$DIR_LIB/.." && rm -rf "$tmp_dir"
        else
            log_warn "TÜBİTAK AKİS sürücüsü indirilemedi, OpenSC kullanılacak."
            cd "$DIR_LIB/.." && rm -rf "$tmp_dir"
        fi
    fi

    # Symlink to user local lib if present
    mkdir -p "$HOME/.local/lib"
    for akis_path in /usr/lib64/libakisp11.so /usr/lib/libakisp11.so /opt/Akia/libakisp11.so; do
        if [[ -f "$akis_path" ]]; then
            ln -sf "$akis_path" "$HOME/.local/lib/libakisp11.so" 2>/dev/null || true
            break
        fi
    done
}

fedora_install_uyap_editor() {
    log_step "4/5: UYAP Doküman Editörü yapılandırılıyor..."

    if has_cmd uyap-dokuman || [[ -f /usr/bin/uyap-dokuman || -f "$HOME/.local/bin/uyap-dokuman" ]]; then
        log_info "UYAP Doküman Editörü sistemde mevcut, başlatıcı kontrol ediliyor..."
    else
        local tmp_dir
        tmp_dir=$(mktemp -d /tmp/uyap-fedora-XXXXXX)

        log_info "Resmi UYAP sunucusundan son sürüm indiriliyor..."
        local zip_url="https://rayp.adalet.gov.tr/resimler/2/dosya/uyapeditor_5.4.20_amd64.zip"

        if curl -sSL -L --connect-timeout 8 --max-time 120 "$zip_url" -o "$tmp_dir/uyap.zip"; then
            cd "$tmp_dir"
            unzip -q uyap.zip
            local deb_file
            deb_file=$(find . -name "*uyapeditor*.deb" -o -name "*uyap*.deb" | head -n 1)

            if [[ -n "$deb_file" && -f "$deb_file" ]]; then
                log_info "UYAP kütüphaneleri ayıklanıyor..."
                require_sudo
                ar x "$deb_file"
                sudo mkdir -p /usr/share/java/uyap-editor
                mkdir -p extract
                tar -xf data.tar.* -C extract
                sudo cp -r extract/usr/share/UYAPEditor/* /usr/share/java/uyap-editor/ 2>/dev/null || true
                if [[ -d extract/usr/share/icons ]]; then
                    sudo cp -r extract/usr/share/icons/* /usr/share/icons/ 2>/dev/null || true
                fi
                log_success "UYAP Doküman Editörü başarıyla kuruldu."
            fi
        fi
        cd "$DIR_LIB/.." && rm -rf "$tmp_dir"
    fi

    # Set up user-level wrapper for Java 11 guarantee
    mkdir -p "$HOME/.local/bin" "$HOME/.local/lib"
    cat << 'EOF' > "$HOME/.local/bin/uyap-dokuman"
#!/bin/bash
# UYAP Editor wrapper for Linux Legal Workstation (Fedora/RHEL)
export LD_LIBRARY_PATH="$HOME/.local/lib:/opt/Akia:/usr/lib64:/usr/lib64/pkcs11:/usr/lib/pkcs11:${LD_LIBRARY_PATH}"

# Find Java 11 or 8 runtime
for jcandidate in \
    "$HOME/.local/share/jvm/temurin-11/bin/java" \
    /usr/lib/jvm/java-11-openjdk/bin/java \
    /usr/lib/jvm/java-11-openjdk-*/bin/java \
    /usr/lib/jvm/java-1.8.0-openjdk/bin/java \
    /usr/bin/java
do
    if [[ -x "$jcandidate" ]]; then
        export UYAP_EDITOR_JAVA="$jcandidate"
        break
    fi
done

if [[ -x /usr/bin/uyap-dokuman ]]; then
    exec /usr/bin/uyap-dokuman "$@"
elif [[ -f /usr/share/java/uyap-editor/editor_lib.jar ]]; then
    exec "${UYAP_EDITOR_JAVA:-java}" -Xmx256m \
        -cp '/usr/share/java/uyap-editor/*' \
        tr.com.havelsan.uyap.system.editor.common.WPAppManager \
        getNewWPInstance EDITOR_TYPE_DOCUMENT "$@"
fi
EOF
    chmod +x "$HOME/.local/bin/uyap-dokuman"

    # Link opensc-pkcs11
    for p11 in /usr/lib64/opensc-pkcs11.so /usr/lib64/pkcs11/opensc-pkcs11.so /usr/lib/opensc-pkcs11.so; do
        if [[ -f "$p11" ]]; then
            ln -sf "$p11" "$HOME/.local/lib/libopensc-pkcs11.so" 2>/dev/null || true
            break
        fi
    done

    log_success "UYAP Doküman Editörü başlatıcıları ve kütüphane yolları hazırlandı."
}

fedora_install_adalet_eimza() {
    log_step "5/5: Adalet E-İmza Uygulaması (Avukat Portal Girişi) kuruluyor..."

    local target_dir="$HOME/.local/lib/adalet-eimza-tray"
    local bin_dir="$HOME/.local/bin"
    local app_dir="$HOME/.local/share/applications"
    local service_dir="$HOME/.config/systemd/user"

    mkdir -p "$target_dir" "$bin_dir" "$app_dir" "$service_dir" "$HOME/.local/lib"

    # AppIndicator compatibility
    for appind in /usr/lib64/libayatana-appindicator3.so.1 /usr/lib64/libappindicator3.so.1 /usr/lib/libayatana-appindicator3.so.1; do
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
        tmp_dir=$(mktemp -d /tmp/eimza-fedora-install-XXXXXX)
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
export LD_LIBRARY_PATH="$HOME/.local/lib:/usr/lib64:${LD_LIBRARY_PATH}"
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
Environment=LD_LIBRARY_PATH=$HOME/.local/lib:/usr/lib64
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
    log_success "Adalet E-İmza servisi Fedora için etkinleştirildi."
}

fedora_install_all() {
    fedora_install_system_packages
    fedora_install_akia
    fedora_install_uyap_editor
    fedora_install_adalet_eimza
    common_install_uets
    common_ensure_akia_desktop
}

