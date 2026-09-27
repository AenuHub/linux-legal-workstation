# CHANGELOG

All notable changes to the `linux-legal-workstation` project will be documented in this file.

## [0.1.0] - 2026-09-27

### Added
- Initial modular project architecture (`install.sh`, `lib/common.sh`, `lib/arch.sh`, `lib/debian.sh`, `lib/fedora.sh`).
- Arch Linux & Omarchy installation engine supporting PC/SC smartcard stack (`pcsclite`, `ccid`, `opensc`).
- Official UYAP Doküman Editörü launcher wrapper with Java 11/8 isolation and PKCS#11 linking.
- Official Adalet E-İmza Uygulaması integration from UYAP CDN with background `systemd --user` service and auto-update tool.
- CLI diagnosis tool `legal-workstation doctor` to inspect readers, token presence, and service health.
- Comprehensive Turkish `README.md` with visual badges and lawyer-friendly instructions.
- Unified suite upgrade command (`legal-workstation upgrade` / `update`) to update CLI, Adalet E-İmza CDN package, UYAP Editor, and restart background services with doctor verification.
- Full Debian, Ubuntu and Linux Mint installation engine (`lib/debian.sh`) supporting apt-get packaging, official UYAP Editor deb installation, and systemd user services.
- Automated container integration test (`tests/test-ubuntu-container.sh`) validating clean-room installation on Ubuntu 22.04 LTS.
- End-to-end physical hardware verification on Omarchy Linux: successfully tested token reader (ACS ACR39U), TÜBİTAK UEKAE AKİS v2.2 card, PIN authentication, and generated signed UDF document containing cryptographic `sign.sgn`.
- Integrated official TÜBİTAK AKİS (`Akia_linux_6_8_10.deb` supplying `libakisp11.so` and AKİA) into Debian/Ubuntu engine, ensuring native driver support for TÜBİTAK UEKAE AKİS v2.2 chipsets on Ubuntu, Debian, and Linux Mint.
- Full Fedora, Red Hat Enterprise Linux (RHEL), Rocky and AlmaLinux engine (`lib/fedora.sh`) with native DNF package resolution, official TÜBİTAK AKİS RPM installation, isolated Eclipse Temurin Java 11 JRE runtime fallback, and automated clean-room container verification test (`tests/test-fedora-container.sh`).
- Enhanced `legal-workstation doctor` to detect user-isolated Temurin Java 11 JRE and alternate distro JVM paths.
- Windows 10/11 one-command installation engine (`install.ps1`) supporting self-elevation, SCardSvr service management, Adoptium Eclipse Temurin 11 MSI, official TÜBİTAK AKİS Windows x64 MSI, UYAP UKI MSI, and dynamic Adalet E-İmza CDN installation.
- Windows CLI diagnosis and upgrade tool (`bin/legal-workstation.ps1` and CMD wrapper `bin/legal-workstation.cmd`).
- Automated container integration test for Windows PowerShell scripts (`tests/test-windows-powershell.sh`) using official Microsoft PowerShell container.
- Non-destructive unified uninstall command (`legal-workstation uninstall`) for both Linux and Windows, removing suite-specific services, launchers, and isolation files while strictly protecting pre-existing user software and drivers.
- Container-verified clean installation and uninstallation test on Ubuntu and Fedora.
- macOS installation engine (`install-macos.sh` and `lib/macos.sh`) with automatic architecture detection (Apple Silicon ARM64 & Intel x86_64), official TÜBİTAK AKİS PKG installation, UYAP Doküman Editörü setup with Gatekeeper quarantine removal (`xattr -cr`), and Adalet E-İmza macOS tray integration.
- macOS support in `legal-workstation doctor` (CryptoTokenKit and reader detection) and `legal-workstation uninstall`.
- Automated test script (`tests/test-macos-syntax.sh`) verifying macOS bash syntax and live HTTP 200 responses from all official TÜBİTAK, UYAP, and CDN endpoints.
- PTT UETS (Ulusal Elektronik Tebligat Sistemi) E-İmza İstemcisi cross-platform integration across Linux (Arch/Omarchy, Ubuntu/Debian, Fedora), macOS (`/Applications/PTT UETS E-İmza.app`), and Windows (`install.ps1`), including desktop launcher shortcuts and official branding icon.
- E-İmza Kart & PIN Yönetimi (PALMA / AKİA) cross-platform integration: Windows silent installation of official TBB TÜRKTRUST/BaroKart PALMA, and Linux/macOS native AKİA desktop launcher with search keywords (`palma`, `pin`, `puk`, `blokaj`, `sertifika`, `turktrust`, `barokart`) for desktop runners (Omarchy-shell, Rofi/Wofi, GNOME, Spotlight).
- Extended `legal-workstation doctor` with PTT UETS and AKİA/PALMA component checks across all platforms.
- Extended `legal-workstation uninstall` to cleanly remove UETS files and shortcuts while preserving existing certificates and system packages.
- Container-verified clean installation on Ubuntu 22.04 LTS, Fedora, Windows PowerShell, and macOS endpoints (all tests passing with exit code 0).
- Comprehensive review and refinement across all scripts and documentation: eliminated awkward phrasing ("Türkiye avukatları" -> "Avukatlar"), removed absolute certainty claims ("kesinlikle", "%100", etc.), updated descriptions to reflect universal multi-platform support (Linux, Windows, macOS), and harmonized banner/help/uninstall messages.
- Fixed Windows PowerShell 5.1 parser error (`TerminatorExpectedAtEndOfString`) caused by UTF-8 byte 0x94 (`✔`) colliding with smart quote in non-BOM PowerShell sessions and here-string line delimiter sensitivity in `bin/legal-workstation.ps1`.
- Added `.gitattributes` to enforce CRLF line endings on Windows PowerShell scripts (`*.ps1`, `*.cmd`, `*.bat`) and UTF-8 BOM encoding.
- Harmonized ASCII banners in `install.ps1`, `install-macos.sh`, and `install.sh` to display 'Legal Workstation' without platform-specific 'Linux' prefix.
- Explicitly marked macOS support as Experimental (Beta) / Community Testing across `README.md` and `install-macos.sh` pending physical hardware verification.
