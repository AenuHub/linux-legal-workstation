# Legal Workstation ⚖️💻

> **Avukatlar için tek komutla UYAP, E-İmza, UETS ve UDF çalışma ortamı (Linux, Windows, macOS).**

[![Arch Linux](https://img.shields.io/badge/Arch_Linux-Omarchy-1793D1?logo=arch-linux&logoColor=white)](https://archlinux.org/)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-E95420?logo=ubuntu&logoColor=white)](https://ubuntu.com/)
[![Fedora](https://img.shields.io/badge/Fedora-51A2DA?logo=fedora&logoColor=white)](https://fedoraproject.org/)
[![Windows](https://img.shields.io/badge/Windows_10%2F11-0078D6?logo=windows&logoColor=white)](https://microsoft.com/windows)
[![macOS](https://img.shields.io/badge/macOS-Deneysel_(Beta)-yellow?logo=apple&logoColor=white)](https://apple.com/macos)
[![Status](https://img.shields.io/badge/Durum-Doğrulandı_(Linux_%26_Windows)-brightgreen)](#)
[![Lisans](https://img.shields.io/badge/Lisans-MIT-blue.svg)](LICENSE)
[![Gizlilik](https://img.shields.io/badge/Gizlilik-No--Exfiltration_(Tamamen_Yerel)-purple)](#gizlilik-ve-güvenlik-ilkesi)

---

## 🎯 Problem ve Vizyon

Avukatlık mesleğini icra ederken farklı işletim sistemlerinde e-imza sürücülerinin (Kamu SM, TÜBİTAK AKİS vb.), akıllı kart okuyucuların (PC/SC), UYAP Doküman Editörü (.udf açma ve imzalama), UETS ve Avukat Portalı girişlerinin kurulumundaki teknik karmaşıklıklar zaman kaybına yol açabilmektedir. İnternetteki dağınık, güncelliğini yitirmiş blog yazıları veya Java sürüm uyuşmazlıkları avukatların iş akışını zorlaştırmaktadır.

**Legal Workstation**, bu teknik engelleri aşmayı ve gerekli çalışma ortamını pratik bir şekilde kurmayı hedefler. Tek bir komutla akıllı kart altyapısını, UYAP Editörü'nü, resmi Adalet E-İmza entegrasyonunu, UETS istemcisini ve kart yönetim araçlarını sisteminize kurar ve yapılandırır.

---

## 🚀 Hızlı Başlangıç (Tek Komutla Kurulum)

### 🐧 Linux (Arch / Omarchy, Ubuntu / Debian / Mint, Fedora / RHEL):
Terminalinizi açın ve aşağıdaki komutu yapıştırıp `Enter` tuşuna basın:

```bash
curl -fsSL https://raw.githubusercontent.com/AenuHub/linux-legal-workstation/main/install.sh | bash
```

### 🪟 Windows (Windows 10 / 11):
PowerShell uygulamasını açın (Yönetici olarak) ve aşağıdaki komutu yapıştırıp `Enter` tuşuna basın:

```powershell
irm https://raw.githubusercontent.com/AenuHub/linux-legal-workstation/main/install.ps1 | iex
```

### 🍎 macOS (Apple Silicon M1-M4 & Intel):
Terminalinizi açın ve aşağıdaki komutu yapıştırıp `Enter` tuşuna basın:

```bash
curl -fsSL https://raw.githubusercontent.com/AenuHub/linux-legal-workstation/main/install-macos.sh | bash
```

*(Veya depoyu klonlayarak çalıştırmak isterseniz):*

```bash
git clone https://github.com/AenuHub/linux-legal-workstation.git
cd linux-legal-workstation
./install.sh        # Linux için
.\install.ps1       # Windows için (PowerShell)
./install-macos.sh  # macOS için
```

---

## 📦 Neler Kurulur ve Yapılandırılır?

Bu kurulum aracı sisteminizde sırasıyla şu katmanları hazırlar:

1. **Akıllı Kart & Donanım Katmanı:**
   - `pcsclite`, `ccid` (USB akıllı kart okuyucu sürücüleri)
   - `opensc` (PKCS#11 akıllı kart kriptografik arayüzü)
   - `pcscd.socket` ve `pcscd.service` otomatik arka plan servisleri.

2. **UYAP Doküman Editörü & Java 11/8 İzolasyonu:**
   - Adalet Bakanlığı UYAP Doküman Editörü kurulumu.
   - Sistemin genel Java ayarlarını bozmadan, UYAP'ın ihtiyaç duyduğu Java 11 JRE ortamının bağlanması.
   - `.udf` dosyalarının doğrudan çift tıklamayla UYAP Editör'de açılması için MIME türü eşleşmesi ve masaüstü kısayolları.
   - UYAP Editör içinden e-imza ile sorunsuz imzalama desteği.

3. **Adalet E-İmza Uygulaması (Avukat Portal Girişi):**
   - Resmi UYAP CDN (`cdn.uyap.gov.tr`) üzerinden en güncel resmi uygulamanın otomatik indirilmesi ve kurulması.
   - Modern Linux masaüstü ortamlarıyla uyumlu `libappindicator` entegrasyonu.
   - Kullanıcı oturum açtığında otomatik çalışan `systemd --user` servis entegrasyonu.
   - Tek komutla sürüm güncelleme mekanizması (`legal-workstation update`).

4. **PTT UETS (Ulusal Elektronik Tebligat Sistemi) E-İmza İstemcisi:**
   - Resmi PTT UETS sunucusundan son sürüm e-imza istemcisi (`uets-eimza.jar`) otomatik kurulumu.
   - Masaüstü uygulama menüsünde ve uygulama başlatıcılarda (Omarchy-shell, Rofi/Wofi, GNOME, Başlat Menüsü, Spotlight) arama ile doğrudan erişim.

5. **E-İmza Kart & PIN Yönetimi (PALMA / AKİA):**
   - **Windows:** Türkiye Barolar Birliği (TBB) resmi dağıtımı olan TÜRKTRUST / BaroKart **PALMA** uygulamasının sessiz kurulumu.
   - **Linux & macOS:** TÜRKTRUST, BaroKart ve TÜBİTAK akıllı kartları için yerel **AKİA** kart yöneticisi. Masaüstü arama menülerinde `palma`, `pin`, `puk`, `blokaj`, `sertifika` anahtar kelimeleriyle anında erişim.

---

## 🩺 Sağlık ve Teşhis Aracı (`doctor`)

Kurulum bittikten sonra veya e-imzanızla ilgili herhangi bir şüphe duyduğunuzda tek bir komutla sisteminizi kontrol edebilirsiniz:

```bash
legal-workstation doctor
```

**Örnek Çıktı:**
```text
=====================================================
  Legal Workstation - Teşhis ve Sağlık Kontrolü
=====================================================

1. Akıllı Kart Servisi (pcscd):  [ÇALIŞIYOR]
2. Kart Okuyucu / USB Token:       [ALGILANDI] (ACS ACR39U ICC Reader)
3. Adalet E-İmza Servisi:         [ÇALIŞIYOR]
4. UYAP Uyumlu Java (8/11):        [MEVCUT] (openjdk version 11.0.32)
5. UYAP Doküman Editörü:        [HAZIR]
6. PTT UETS E-İmza İstemcisi:    [HAZIR]
7. E-İmza PIN & Kart (AKİA):     [HAZIR]

✔ Sisteminiz UYAP ve E-İmza kullanımı için hazırdır!
```

---

## 🔄 Tek Komutla Tüm Paketi Güncelleme (`upgrade`)

Adalet Bakanlığı UYAP Portal e-imza uygulamasını veya UYAP Doküman Editörü'nü güncellediğinde, tek bir komutla tüm çalışma ortamınızı, sürücülerinizi ve servislerinizi senkronize edebilirsiniz:

```bash
legal-workstation upgrade
```

Bu komut sırasıyla:
1. `linux-legal-workstation` araçlarını günceller,
2. Adalet Bakanlığı CDN'inden (`cdn.uyap.gov.tr`) en son E-İmza Uygulaması sürümünü sorgular ve günceller,
3. UYAP Doküman Editörü güncellemelerini kontrol eder,
4. Arka plan servislerini (`adalet-eimza-tray`, `pcscd`) güvenli şekilde yeniden başlatır,
5. Otomatik `doctor` teşhisi yaparak sistemin hazır olduğunu teyit eder.

---

## 🗑️ Güvenli ve Temiz Kaldırma (`uninstall`)

Kurulum paketinin kurduğu tüm servisleri, masaüstü kısayollarını ve başlatıcıları sistemden kaldırmak istediğinizde tek bir komut çalıştırmanız yeterlidir:

```bash
legal-workstation uninstall
```

*(Windows için de PowerShell veya CMD üzerinden aynı komut geçerlidir: `legal-workstation uninstall`)*

> [!NOTE]
> **Güvenlik ve İzolasyon İlkesi:** Bu kaldırma komutu **yalnızca** bu aracın kurduğu servisleri, başlatıcıları ve izole bileşenleri kaldırır. Bilgisayarınızda önceden veya manuel olarak kurulu olan genel sistem paketlerinize, sürücülerinize ya da kişisel dosyalarınıza dokunmayacak şekilde tasarlanmıştır.

---

## 🗺️ Desteklenen Platformlar ve Yol Haritası

- [x] **Arch Linux & Omarchy:** Donanım düzeyinde fiziksel olarak (ACS ACR39U + AKİS v2.2) test edildi ve üretimde doğrulandı.
- [x] **Ubuntu, Debian & Linux Mint (v20.04+, v22.04+, v24.04+):** Destek eklendi ve resmi TÜBİTAK AKİS sürücüsüyle konteynerde doğrulandı (`lib/debian.sh`).
- [x] **Fedora, RHEL & Rocky Linux:** Destek eklendi, Temurin Java 11 ve AKİS RPM ile konteynerde doğrulandı (`lib/fedora.sh`).
- [x] **Windows (10 / 11):** Tek komutla PowerShell kurulumu (`install.ps1`), SCardSvr servisi, Java 11, UETS ve PALMA entegrasyonu tamamlandı.
- [ ] **macOS (Apple Silicon & Intel):** **Deneysel (Beta) / Topluluk Testi.** Kurulum motoru ve resmi paket bağlantıları doğrulandı; henüz gerçek bir Mac cihazında uçtan uca fiziksel donanım testi yapılmadığı için topluluk geri bildirimine ve testlerine açıktır.

---

## 🛡️ Gizlilik ve Güvenlik İlkesi (No-Exfiltration)

* **Sıfır Telemetri:** Hiçbir kullanıcı verisi, belge adı, sertifika bilgisi veya dosya içeriği toplanmaz, kaydedilmez veya harici sunuculara aktarılmaz.
* **Resmi Kaynaklar:** İndirilen tüm paketler (Adalet E-İmza, UYAP Editör vb.) doğrudan Adalet Bakanlığı'nın ve TÜBİTAK'ın resmi CDN adreslerinden çekilir.
* **Açık Kaynak Şeffaflığı:** Tüm kurulum adımları ve betikler bu depoda açık ve denetlenebilir durumdadır.

---

## 📄 Lisans

Bu proje [MIT Lisansı](LICENSE) altında sunulmaktadır.
EOF
