# Linux Legal Workstation ⚖️🐧

> **Türkiye'deki avukatlar için Linux üzerinde tek komutla UYAP, E-İmza ve UDF çalışma ortamı.**

[![Arch Linux](https://img.shields.io/badge/Arch_Linux-Omarchy-1793D1?logo=arch-linux&logoColor=white)](https://archlinux.org/)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-E95420?logo=ubuntu&logoColor=white)](https://ubuntu.com/)
[![Fedora](https://img.shields.io/badge/Fedora-51A2DA?logo=fedora&logoColor=white)](https://fedoraproject.org/)
[![Status](https://img.shields.io/badge/Durum-Doğrulandı_(Linux_Tamamlandı)-brightgreen)](#)
[![Lisans](https://img.shields.io/badge/Lisans-MIT-blue.svg)](LICENSE)
[![Gizlilik](https://img.shields.io/badge/Gizlilik-No--Exfiltration_(Tamamen_Yerel)-purple)](#gizlilik-ve-güvenlik-ilkesi)

---

## 🎯 Problem ve Vizyon

Türkiye'de avukatlık mesleğini icra ederken Linux kullanmanın önündeki en büyük engel; e-imza sürücülerinin (Kamu SM, TÜBİTAK AKİS vb.), kart okuyucuların (PC/SC), UYAP Doküman Editörü (.udf açma ve imzalama) ile Avukat Portalı girişlerinin kurulumundaki teknik zorluklardı. Avukatlar internetteki dağınık, güncelliğini yitirmiş blog yazıları veya Java çakışmaları arasında kaybolup çoğu zaman mecburen Windows'a geri dönmekteydi.

**Linux Legal Workstation**, bu engelleri tamamen ortadan kaldırır. Tek bir komutla tüm akıllı kart altyapısını, UYAP Editörü'nü ve resmi Adalet E-İmza entegrasyonunu sisteminize kurar ve doğrular.

---

## 🚀 Hızlı Başlangıç (Tek Komutla Kurulum)

Terminalinizi açın ve aşağıdaki komutu yapıştırıp `Enter` tuşuna basın:

```bash
curl -fsSL https://raw.githubusercontent.com/AenuHub/linux-legal-workstation/main/install.sh | bash
```

*(Veya depoyu klonlayarak çalıştırmak isterseniz):*

```bash
git clone https://github.com/AenuHub/linux-legal-workstation.git
cd linux-legal-workstation
./install.sh
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

4. **AKİS / AKİA (TÜBİTAK Kart İzleme Aracı):**
   - E-imza PIN kodunu değiştirme, bloke kaldırma ve sertifika geçerlilik sürelerini kontrol etmek için AKİA entegrasyonu.

---

## 🩺 Sağlık ve Teşhis Aracı (`doctor`)

Kurulum bittikten sonra veya e-imzanızla ilgili herhangi bir şüphe duyduğunuzda tek bir komutla sisteminizi kontrol edebilirsiniz:

```bash
legal-workstation doctor
```

**Örnek Çıktı:**
```text
=====================================================
  Linux Legal Workstation - Teşhis ve Sağlık Kontrolü
=====================================================

1. Akıllı Kart Servisi (pcscd):  [ÇALIŞIYOR]
2. Kart Okuyucu / USB Token:       [ALGILANDI] (ACS ACR38U-CCID)
3. Adalet E-İmza Servisi:         [ÇALIŞIYOR]
4. UYAP Uyumlu Java (8/11):        [MEVCUT] (openjdk version 11.0.32)
5. UYAP Doküman Editörü:        [HAZIR]

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

## 🗺️ Desteklenen Platformlar ve Yol Haritası

- [x] **Arch Linux & Omarchy:** Tamamen test edildi, donanım düzeyinde doğrulandı ve üretimde çalışıyor.
- [x] **Ubuntu, Debian & Linux Mint (v20.04+, v22.04+, v24.04+):** Destek eklendi ve resmi TÜBİTAK AKİS sürücüsüyle konteynerde doğrulandı (`lib/debian.sh`).
- [x] **Fedora, RHEL & Rocky Linux:** Destek eklendi, Temurin Java 11 ve AKİS RPM ile konteynerde doğrulandı (`lib/fedora.sh`).
- [ ] **macOS:** Tek komutla e-imza ve UYAP kurulum motoru (`install-macos.sh` - Yakında).
- [ ] **Windows:** Tek komutla izole avukat çalışma ortamı (`install.ps1` - Yakında).

---

## 🛡️ Gizlilik ve Güvenlik İlkesi (No-Exfiltration)

* **Sıfır Telemetri:** Hiçbir kullanıcı verisi, belge adı, sertifika bilgisi veya dosya içeriği toplanmaz, kaydedilmez veya harici sunuculara aktarılmaz.
* **Resmi Kaynaklar:** İndirilen tüm paketler (Adalet E-İmza, UYAP Editör vb.) doğrudan Adalet Bakanlığı'nın ve TÜBİTAK'ın resmi CDN adreslerinden çekilir.
* **Açık Kaynak Şeffaflığı:** Tüm kurulum adımları ve betikler bu depoda açık ve denetlenebilir durumdadır.

---

## 📄 Lisans

Bu proje [MIT Lisansı](LICENSE) altında sunulmaktadır.
EOF
