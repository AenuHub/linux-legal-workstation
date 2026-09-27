#!/usr/bin/env bash
# Automated verification test for macOS Legal Workstation installer and download endpoints
set -euo pipefail

DIR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Legal Workstation - macOS Kurulum Motoru Doğrulama Testi Başlatılıyor..."

echo "==> 1. Sözdizimi Analizi (bash -n)..."
bash -n "$DIR_ROOT/install-macos.sh"
bash -n "$DIR_ROOT/lib/macos.sh"
echo "  -> [GEÇTİ] macOS betikleri sözdizimi hatasız."

echo "==> 2. TÜBİTAK AKİS macOS Paket Uç Noktaları Test Ediliyor..."
AKIS_ARM="https://akiskart.bilgem.tubitak.gov.tr/wp-content/uploads/sites/33/2026/06/Akia_macos_arm_6.8.10.pkg_.zip"
AKIS_INTEL="https://akiskart.bilgem.tubitak.gov.tr/wp-content/uploads/sites/33/2026/06/Akia_macos_intel_6.8.10.pkg_.zip"

CODE_ARM=$(curl -sI -L --connect-timeout 8 --max-time 15 -o /dev/null -w "%{http_code}" "$AKIS_ARM" || echo "000")
CODE_INTEL=$(curl -sI -L --connect-timeout 8 --max-time 15 -o /dev/null -w "%{http_code}" "$AKIS_INTEL" || echo "000")
echo "  AKİS macOS ARM HTTP Durumu: $CODE_ARM"
echo "  AKİS macOS Intel HTTP Durumu: $CODE_INTEL"

if [[ "$CODE_ARM" != "200" && "$CODE_ARM" != "302" ]]; then
    echo "  [HATA] AKİS macOS ARM paketi indirilemiyor!"
    exit 1
fi
if [[ "$CODE_INTEL" != "200" && "$CODE_INTEL" != "302" ]]; then
    echo "  [HATA] AKİS macOS Intel paketi indirilemiyor!"
    exit 1
fi
echo "  -> [GEÇTİ] TÜBİTAK AKİS macOS paket bağlantıları canlı ve doğrulanmış."

echo "==> 3. UYAP Doküman Editörü macOS Resmi Paket Uç Noktaları Test Ediliyor..."
UYAP_ARM="https://rayp.adalet.gov.tr/resimler/2/dosya/UyapDokumanEditoru-AppleSilicon-5.4.21.zip"
UYAP_INTEL="https://rayp.adalet.gov.tr/resimler/2/dosya/UyapDokumanEditoru-Intel-5.4.21.zip"

CODE_UYAP_ARM=$(curl -sI -L --connect-timeout 8 --max-time 15 -o /dev/null -w "%{http_code}" "$UYAP_ARM" || echo "000")
CODE_UYAP_INTEL=$(curl -sI -L --connect-timeout 8 --max-time 15 -o /dev/null -w "%{http_code}" "$UYAP_INTEL" || echo "000")
echo "  UYAP Editör macOS Apple Silicon HTTP Durumu: $CODE_UYAP_ARM"
echo "  UYAP Editör macOS Intel HTTP Durumu: $CODE_UYAP_INTEL"

if [[ "$CODE_UYAP_ARM" != "200" && "$CODE_UYAP_ARM" != "302" ]]; then
    echo "  [HATA] UYAP macOS ARM paketi indirilemiyor!"
    exit 1
fi
if [[ "$CODE_UYAP_INTEL" != "200" && "$CODE_UYAP_INTEL" != "302" ]]; then
    echo "  [HATA] UYAP macOS Intel paketi indirilemiyor!"
    exit 1
fi
echo "  -> [GEÇTİ] UYAP Doküman Editörü macOS paket bağlantıları canlı ve doğrulanmış."

echo "==> 4. Adalet E-İmza UYAP CDN Canlı Sürüm ve URL Sorgusu (mac_arm & mac_intel)..."
CDN_DATA=$(curl -sSL --connect-timeout 6 --max-time 15 "https://cdn.uyap.gov.tr/framework/public/latest.json")
VER_ARM=$(python3 -c "import json, sys; d=json.loads(sys.argv[1]); print(d['releases']['mac_arm']['latestVersion'])" "$CDN_DATA")
URL_ARM=$(python3 -c "import json, sys; d=json.loads(sys.argv[1]); print(d['releases']['mac_arm']['downloadUrl'])" "$CDN_DATA")
VER_INTEL=$(python3 -c "import json, sys; d=json.loads(sys.argv[1]); print(d['releases']['mac_intel']['latestVersion'])" "$CDN_DATA")
URL_INTEL=$(python3 -c "import json, sys; d=json.loads(sys.argv[1]); print(d['releases']['mac_intel']['downloadUrl'])" "$CDN_DATA")

echo "  Adalet E-İmza Apple Silicon: v$VER_ARM ($URL_ARM)"
echo "  Adalet E-İmza Intel: v$VER_INTEL ($URL_INTEL)"

CODE_CDN_ARM=$(curl -sI -L --connect-timeout 8 --max-time 15 -o /dev/null -w "%{http_code}" "$URL_ARM" || echo "000")
if [[ "$CODE_CDN_ARM" != "200" && "$CODE_CDN_ARM" != "302" ]]; then
    echo "  [HATA] Adalet E-İmza macOS paketi indirilemiyor!"
    exit 1
fi
echo "  -> [GEÇTİ] Adalet E-İmza macOS resmi CDN paketleri canlı ve erişilebilir."

echo "==> 5. PTT UETS E-İmza İstemcisi Uç Noktası Test Ediliyor..."
UETS_URL="https://api.etebligat.gov.tr/v1/auth/_eimza/uets-eimza.jar"
CODE_UETS=$(curl -s -L --connect-timeout 8 --max-time 15 -r 0-1024 -o /dev/null -w "%{http_code}" "$UETS_URL" || echo "000")
echo "  PTT UETS İstemci HTTP Durumu: $CODE_UETS"
if [[ "$CODE_UETS" != "200" && "$CODE_UETS" != "206" && "$CODE_UETS" != "302" ]]; then
    echo "  [HATA] PTT UETS istemcisi indirilemiyor!"
    exit 1
fi
echo "  -> [GEÇTİ] PTT UETS E-İmza resmi istemcisi canlı ve erişilebilir."

echo
echo "==> [BAŞARILI] macOS motoru uçtan uca kaynak ve sözdizimi doğrulaması başarıyla tamamlandı!"

