#!/usr/bin/env bash
# Legal Workstation - Windows kaldirma davranis testleri (pwsh, docker).
set -euo pipefail

DIR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Windows kaldirma davranis testleri baslatiliyor..."

docker run --rm \
    -v "$DIR_ROOT:/workspace" \
    -w /workspace \
    -e LW_REPO_ROOT=/workspace \
    -e LW_TEST_ROOT=/tmp/lwtest \
    mcr.microsoft.com/powershell:latest \
    pwsh -NoProfile -Command '
        New-Item -ItemType Directory -Path $env:LW_TEST_ROOT -Force | Out-Null
        & /workspace/tests/windows/manifest.tests.ps1
        if ($LASTEXITCODE) { exit $LASTEXITCODE }
        & /workspace/tests/windows/cli.tests.ps1
        if ($LASTEXITCODE) { exit $LASTEXITCODE }
        & /workspace/tests/windows/uninstall.tests.ps1
        if ($LASTEXITCODE) { exit $LASTEXITCODE }
    '

echo
echo "==> [BASARILI] Windows kaldirma davranis testleri tamamlandi!"
