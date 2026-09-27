#!/usr/bin/env bash
# Automated verification test for Linux Legal Workstation in Ubuntu container
set -euo pipefail

DIR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Legal Workstation - Ubuntu 22.04 Temiz Konteyner Doğrulama Testi Başlatılıyor..."

docker run --rm \
    -v "$DIR_ROOT:/workspace" \
    -w /workspace \
    ubuntu:22.04 \
    bash -c "/workspace/install.sh && /root/.local/bin/legal-workstation doctor"

echo
echo "==> [BAŞARILI] Ubuntu konteyner entegrasyon testi başarıyla tamamlandı!"
