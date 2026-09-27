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
