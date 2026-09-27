#!/usr/bin/env bash
# macOS installation engine for Linux Legal Workstation (Apple Silicon & Intel)
# Supported: macOS Monterey (12+), Ventura (13+), Sonoma (14+), Sequoia (15+)

DIR_LIB="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck disable=SC1091
source "$DIR_LIB/common.sh"

macos_detect_arch() {
    local m
    m=$(uname -m)
    case "$m" in
        arm64|aarch64)
            echo "arm64"
            ;;
        x86_64)
            echo "intel"
            ;;
        *)
            echo "intel"
            ;;
    esac
}

macos_install_akia() {
    log_step "1/4: TÜBİTAK AKİS / AKİA (libakisp11) akıllı kart sürücüsü kuruluyor..."

    local arch
    arch=$(macos_detect_arch)
    log_info "Tespit edilen macOS mimarisi: ${BOLD}$arch${NC}"

    if [[ -d /Applications/Akia.app || -f /usr/local/lib/libakisp11.dylib ]]; then
        log_info "TÜBİTAK AKİS / AKİA sürücüsü sistemde mevcut."
        return 0
    fi

    local pkg_url=""
    if [[ "$arch" == "arm64" ]]; then
        pkg_url="https://akiskart.bilgem.tubitak.gov.tr/wp-content/uploads/sites/33/2026/06/Akia_macos_arm_6.8.10.pkg_.zip"
    else
        pkg_url="https://akiskart.bilgem.tubitak.gov.tr/wp-content/uploads/sites/33/2026/06/Akia_macos_intel_6.8.10.pkg_.zip"
    fi

    local tmp_dir
    tmp_dir=$(mktemp -d /tmp/akia-macos-XXXXXX)
    log_info "Resmi TÜBİTAK BILGEM sunucusundan AKİS macOS paketi indiriliyor..."
    if curl -sSL -L --connect-timeout 8 --max-time 180 "$pkg_url" -o "$tmp_dir/akia.zip"; then
        cd "$tmp_dir"
        unzip -q akia.zip
        local pkg_file
        pkg_file=$(find . -name "*.pkg" | head -n 1)
        if [[ -n "$pkg_file" && -f "$pkg_file" ]]; then
            require_sudo
            log_info "AKİS sürücüsü sisteme yükleniyor..."
            sudo installer -pkg "$pkg_file" -target /
            log_success "TÜBİTAK AKİS sürücüsü ve AKİA başarıyla kuruldu."
        fi
        cd "$DIR_LIB/.." && rm -rf "$tmp_dir"
    else
        log_warn "TÜBİTAK AKİS sürücüsü otomatik indirilemedi. https://akiskart.bilgem.tubitak.gov.tr adresini ziyaret edebilirsiniz."
        cd "$DIR_LIB/.." && rm -rf "$tmp_dir"
    fi
}

macos_install_uyap_editor() {
    log_step "2/4: UYAP Doküman Editörü (Resmi Adalet Bakanlığı Sürümü) kuruluyor..."

    if [[ -d "/Applications/UyapDokumanEditoru.app" || -d "$HOME/Applications/UyapDokumanEditoru.app" ]]; then
        log_info "UYAP Doküman Editörü sistemde mevcut."
        return 0
    fi

    local arch
    arch=$(macos_detect_arch)
    local uyap_url=""

    if [[ "$arch" == "arm64" ]]; then
        log_info "Apple Silicon (ARM64) uyumlu UYAP Editör indiriliyor..."
        uyap_url="https://rayp.adalet.gov.tr/resimler/2/dosya/UyapDokumanEditoru-AppleSilicon-5.4.21.zip"
    else
        log_info "Intel (x86_64) uyumlu UYAP Editör indiriliyor..."
        uyap_url="https://rayp.adalet.gov.tr/resimler/2/dosya/UyapDokumanEditoru-Intel-5.4.21.zip"
    fi

    local tmp_dir
    tmp_dir=$(mktemp -d /tmp/uyap-macos-XXXXXX)
    if curl -sSL -L --connect-timeout 8 --max-time 240 "$uyap_url" -o "$tmp_dir/uyap.zip"; then
        cd "$tmp_dir"
        log_info "UYAP paketi ayıklanıyor..."
        unzip -q uyap.zip

        local app_path
        app_path=$(find . -maxdepth 2 -name "UyapDokumanEditoru.app" -o -name "*.app" | head -n 1)

        if [[ -n "$app_path" && -d "$app_path" ]]; then
            require_sudo
            sudo rm -rf "/Applications/UyapDokumanEditoru.app"
            sudo cp -R "$app_path" "/Applications/UyapDokumanEditoru.app"

            # Remove Gatekeeper quarantine so macOS allows opening without error
            sudo xattr -cr "/Applications/UyapDokumanEditoru.app" 2>/dev/null || true
            log_success "UYAP Doküman Editörü /Applications/UyapDokumanEditoru.app konumuna kuruldu."
        fi
        cd "$DIR_LIB/.." && rm -rf "$tmp_dir"
    else
        log_warn "UYAP Doküman Editörü indirilemedi."
        cd "$DIR_LIB/.." && rm -rf "$tmp_dir"
    fi
}

macos_install_adalet_eimza() {
    log_step "3/4: Adalet E-İmza Uygulaması (Avukat Portal Girişi) kuruluyor..."

    local arch
    arch=$(macos_detect_arch)
    local cdn_json_url="https://cdn.uyap.gov.tr/framework/public/latest.json"

    log_info "Resmi UYAP CDN üzerinden son sürüm sorgulanıyor..."
    local latest_data
    latest_data=$(curl -sSL --connect-timeout 6 --max-time 15 "$cdn_json_url" 2>/dev/null || true)

    local download_url=""
    local latest_version=""

    if [[ -n "$latest_data" ]] && has_cmd python3; then
        if [[ "$arch" == "arm64" ]]; then
            latest_version=$(python3 -c "import json, sys; d=json.loads(sys.argv[1]); print(d['releases']['mac_arm']['latestVersion'])" "$latest_data" 2>/dev/null || true)
            download_url=$(python3 -c "import json, sys; d=json.loads(sys.argv[1]); print(d['releases']['mac_arm']['downloadUrl'])" "$latest_data" 2>/dev/null || true)
        else
            latest_version=$(python3 -c "import json, sys; d=json.loads(sys.argv[1]); print(d['releases']['mac_intel']['latestVersion'])" "$latest_data" 2>/dev/null || true)
            download_url=$(python3 -c "import json, sys; d=json.loads(sys.argv[1]); print(d['releases']['mac_intel']['downloadUrl'])" "$latest_data" 2>/dev/null || true)
        fi
    fi

    if [[ -n "$download_url" ]]; then
        log_info "Sürüm: v${latest_version} ($arch) indiriliyor: $download_url"
        local tmp_dir
        tmp_dir=$(mktemp -d /tmp/eimza-macos-XXXXXX)
        curl -sSL --progress-bar "$download_url" -o "$tmp_dir/eimza.zip"

        cd "$tmp_dir"
        unzip -q eimza.zip
        local app_path
        app_path=$(find . -maxdepth 2 -name "*adalet*eimza*.app" -o -name "*.app" | head -n 1)

        if [[ -n "$app_path" && -d "$app_path" ]]; then
            require_sudo
            sudo rm -rf "/Applications/Adalet E-İmza Tray.app"
            sudo cp -R "$app_path" "/Applications/Adalet E-İmza Tray.app"
            sudo xattr -cr "/Applications/Adalet E-İmza Tray.app" 2>/dev/null || true
            log_success "Adalet E-İmza Uygulaması v$latest_version kuruldu."

            # Add to macOS Login Items
            osascript -e 'tell application "System Events" to make login item at end with properties {path:"/Applications/Adalet E-İmza Tray.app", hidden:false}' 2>/dev/null || true
            
            # Start tray application
            open -a "/Applications/Adalet E-İmza Tray.app" 2>/dev/null || true
            log_success "Adalet E-İmza sistem tepsisi (tray) servisi başlatıldı."
        fi
        cd "$DIR_LIB/.." && rm -rf "$tmp_dir"
    else
        log_warn "Adalet E-İmza CDN indirme bağlantısı alınamadı."
    fi
}

macos_install_uets() {
    log_step "4/4: PTT UETS (Ulusal Elektronik Tebligat Sistemi) E-İmza İstemcisi kuruluyor..."

    local uets_url="https://api.etebligat.gov.tr/v1/auth/_eimza/uets-eimza.jar"
    local uets_dir="/opt/uets"
    local jar_path="$uets_dir/uets-eimza.jar"
    local app_path="/Applications/PTT UETS E-İmza.app"
    local launcher_path="/usr/local/bin/uets-eimza"

    require_sudo
    sudo mkdir -p "$uets_dir" /usr/local/bin

    log_info "Resmi PTT UETS sunucusundan uets-eimza.jar indiriliyor..."
    local tmp_jar
    tmp_jar=$(mktemp /tmp/uets-jar-XXXXXX.jar)

    if curl -sSL -L --connect-timeout 8 --max-time 120 "$uets_url" -o "$tmp_jar"; then
        sudo cp "$tmp_jar" "$jar_path"
        sudo chmod 644 "$jar_path"
        rm -f "$tmp_jar"

        # Create CLI launcher
        sudo tee "$launcher_path" > /dev/null << 'EOF'
#!/usr/bin/env bash
# PTT UETS E-İmza macOS Launcher
exec java -jar /opt/uets/uets-eimza.jar "$@"
EOF
        sudo chmod +x "$launcher_path"

        # Create macOS Application Bundle for Spotlight and Launchpad
        sudo mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
        sudo tee "$app_path/Contents/MacOS/uets-eimza" > /dev/null << 'EOF'
#!/bin/bash
exec java -jar /opt/uets/uets-eimza.jar
EOF
        sudo chmod +x "$app_path/Contents/MacOS/uets-eimza"

        sudo tee "$app_path/Contents/Info.plist" > /dev/null << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>uets-eimza</string>
    <key>CFBundleIdentifier</key>
    <string>tr.gov.ptt.uets.eimza</string>
    <key>CFBundleName</key>
    <string>PTT UETS E-İmza</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
</dict>
</plist>
EOF
        sudo xattr -cr "$app_path" 2>/dev/null || true
        log_success "PTT UETS E-İmza /Applications/PTT UETS E-İmza.app konumuna kuruldu."
    else
        rm -f "$tmp_jar"
        log_warn "PTT UETS istemcisi indirilemedi."
    fi
}

macos_install_all() {
    macos_install_akia
    macos_install_uyap_editor
    macos_install_adalet_eimza
    macos_install_uets
}

