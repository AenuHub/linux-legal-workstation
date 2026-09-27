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
- Integrated official TÜBİTAK AKİS (`Akia_linux_6_8_10.deb` supplying `libakisp11.so` and AKİA) into Debian/Ubuntu engine, ensuring 100% driver parity for TÜBİTAK UEKAE AKİS v2.2 chipsets on Ubuntu, Debian, and Linux Mint.
- Full Fedora, Red Hat Enterprise Linux (RHEL), Rocky and AlmaLinux engine (`lib/fedora.sh`) with native DNF package resolution, official TÜBİTAK AKİS RPM installation, isolated Eclipse Temurin Java 11 JRE runtime fallback, and automated clean-room container verification test (`tests/test-fedora-container.sh`).
- Enhanced `legal-workstation doctor` to detect user-isolated Temurin Java 11 JRE and alternate distro JVM paths.
- Windows 10/11 one-command installation engine (`install.ps1`) supporting self-elevation, SCardSvr service management, Adoptium Eclipse Temurin 11 MSI, official TÜBİTAK AKİS Windows x64 MSI, UYAP UKI MSI, and dynamic Adalet E-İmza CDN installation.
- Windows CLI diagnosis and upgrade tool (`bin/legal-workstation.ps1` and CMD wrapper `bin/legal-workstation.cmd`).
- Automated container integration test for Windows PowerShell scripts (`tests/test-windows-powershell.sh`) using official Microsoft PowerShell container.
