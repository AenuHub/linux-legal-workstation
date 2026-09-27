#!/usr/bin/env bash
# Automated verification test for Linux Legal Workstation in Fedora container
set -euo pipefail

DIR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Legal Workstation - Fedora Temiz Konteyner Doğrulama Testi Başlatılıyor..."

docker run --rm \
    -v "$DIR_ROOT:/workspace" \
    -w /workspace \
    fedora:latest \
    bash -c "/workspace/install.sh && /root/.local/bin/legal-workstation doctor"

echo
echo "==> [BAŞARILI] Fedora konteyner entegrasyon testi başarıyla tamamlandı!"
