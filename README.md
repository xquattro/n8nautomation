# n8n Self-Hosted Setup für Ubuntu 26

Bu repository, **n8n** workflow automation platformunu Ubuntu 26 VPS'ine kurmanız için gerekli dosyları içerir.

## 📋 Kurulum Gereksinimleri

- **İşletim Sistemi:** Ubuntu 26 (Jammy Jellyfish veya daha yeni)
- **RAM:** Minimum 2GB (4GB+ önerilir)
- **Disk:** Minimum 10GB boş alan
- **İnternet:** Docker ve paketleri indirmek için
- **Port Erişimi:** 
  - 80 (HTTP)
  - 443 (HTTPS)
  - 5678 (n8n web interface)
  - 5432 (PostgreSQL - isteğe bağlı)

## 🚀 Hızlı Başlangıç

### 1. Repository'yi Klonlayın

```bash
git clone https://github.com/xquattro/n8nautomation.git
cd n8nautomation
```

### 2. Setup Script'i Çalıştırın

```bash
sudo bash setup.sh
```

Bu script otomatik olarak:
- ✓ Docker yükler
- ✓ Docker Compose yükler
- ✓ n8n stack dizini oluşturur (`~/n8n-stack`)
- ✓ SSL sertifikası yapılandırır
- ✓ Environment dosyası oluşturur

### 3. Hizmetleri Başlatın

```bash
cd ~/n8n-stack
docker-compose up -d
```

### 4. n8n'e Erişin

```
https://localhost  (SSL ile)
veya
http://localhost:5678  (doğrudan)
```

## 📁 Dosya Yapısı

```
n8nautomation/
├── docker-compose.yml       # Docker Compose konfigürasyonu
├── nginx.conf              # Nginx reverse proxy config
├── setup.sh                # Otomatik kurulum scripti
├── quick-start.sh          # Yönetim için hızlı start script
├── .env.example            # Environment variables şablonu
└── README.md              # Bu dosya

~/n8n-stack/               # Setup script tarafından oluşturulur
├── .env                    # Environment konfigürasyonu
├── docker-compose.yml      # (copied from repo)
├── nginx.conf             # (copied from repo)
├── ssl/
│   ├── cert.pem           # SSL sertifikası
│   └── key.pem            # SSL private key
└── data/                  # Persisten veriler
```

## 🔧 Konfigürasyon

### Environment Değişkenleri (`.env`)

```bash
# Veritabanı
DB_PASSWORD=securepassword123

# n8n
N8N_HOST=0.0.0.0
N8N_DOMAIN=n8n.yourdomain.com
TIMEZONE=Europe/Istanbul

# SSL
SSL_CERT_PATH=/etc/nginx/ssl/cert.pem
SSL_KEY_PATH=/etc/nginx/ssl/key.pem
```

### PostgreSQL Veritabanı

- **Host:** localhost
- **Port:** 5432
- **Database:** n8n
- **User:** n8n
- **Password:** `.env` dosyasındaki `DB_PASSWORD`

## 📝 Kullanım Örnekleri

### Hizmetleri Yönetme

```bash
# Tüm servisleri başlat
docker-compose up -d

# Servisleri durdur
docker-compose down

# Servisleri yeniden başlat
docker-compose restart

# Durumunu kontrol et
docker-compose ps

# Logları görüntüle
docker-compose logs -f n8n
```

### Hızlı Start Script'i Kullanın

```bash
chmod +x quick-start.sh
./quick-start.sh
```

Menüden:
1. Servisleri başlat/durdur/yeniden başlat
2. Durumu kontrol et
3. Logları izle
4. n8n container'ına bağlan
5. Veritabanına erişim sağla
6. n8n'i güncelle

## 🔐 SSL/TLS Yapılandırması

### Seçenek 1: Kendinden İmzalı Sertifika (Test)

```bash
# setup.sh çalıştırırken 1. seçeneği seçin
sudo bash setup.sh
```

**Avantajlar:** Hızlı, ücretsiz  
**Dezavantajlar:** Tarayıcı uyarıları gösterir

### Seçenek 2: Let's Encrypt (Üretim)

```bash
# setup.sh çalıştırırken 2. seçeneği seçin
sudo bash setup.sh
```

Gereken: Domain adı ve e-mail

**Avantajlar:** Ücretsiz, güvenilir, tarayıcı uyarısı yok  
**Dezavantajlar:** Domain ve e-mail gerekli

### Seçenek 3: Özel Sertifika

```bash
# Kendi sertifikalarınızı kullanın
cp /path/to/your/cert.pem ~/n8n-stack/ssl/
cp /path/to/your/key.pem ~/n8n-stack/ssl/
```

## 🔄 Yükseltme

```bash
cd ~/n8n-stack

# En son n8n imajını indir
docker-compose pull

# Containerları yeniden oluştur
docker-compose up -d
```

## 🐛 Sorun Giderme

### Port 5678 Kullanımda

```bash
# Kullanan prosesi bul
sudo lsof -i :5678

# Kapat (PID yerine gerçek ID koy)
sudo kill -9 <PID>
```

### Docker Daemon Başlamıyor

```bash
sudo systemctl start docker
sudo systemctl status docker
sudo journalctl -u docker
```

### n8n Container Crash Oluyor

```bash
# Logları kontrol et
docker-compose logs n8n

# Tüm containerları kapat ve temizle
docker-compose down
docker-compose pull
docker-compose up -d
```

### Veritabanı Hataları

```bash
# PostgreSQL container'ını kontrol et
docker-compose logs postgres

# Veritabanını sıfırla (DİKKAT: Tüm veriler silinir!)
docker-compose down -v
docker-compose up -d
```

### SSL Sertifikası Sorunu

```bash
# Sertifikayı kontrol et
openssl x509 -in ~/n8n-stack/ssl/cert.pem -text -noout

# Nginx konfigürasyonunu test et
docker-compose exec nginx nginx -t

# Nginx'i yeniden başlat
docker-compose restart nginx
```

## 📊 Demo Workflow Oluşturma

n8n'e login olduktan sonra:

1. **+ New Workflow** tıkla
2. **Webhook** trigger ekle
3. **HTTP Request** node ekle
4. GET: `https://jsonplaceholder.typicode.com/posts/1`
5. **Test** tab'ında webhook URL'ini kopyala
6. Browser'da test et: `curl -X POST <webhook-url>`
7. Response göreceksin

## 🔗 Webhook Yapılandırması

n8n'de webhooks şu formatta çalışır:

```
https://n8n.yourdomain.com/webhook/workflow_id
```

Firewall kurallarında 443 portunun açık olduğundan emin ol.

## 📞 Destek & Kaynaklar

- **n8n Docs:** https://docs.n8n.io/
- **n8n GitHub:** https://github.com/n8nio/n8n
- **Docker Docs:** https://docs.docker.com/
- **PostgreSQL Docs:** https://www.postgresql.org/docs/

## 📜 Lisans

Bu kurulum dosyaları MIT lisansı altında yayınlanmıştır.

## 🤝 Katkı

Sorun bulduğunuz veya iyileştirme öneriniz varsa GitHub issues açabilirsiniz.

---

**Sürüm:** 1.0.0  
**Son Güncelleme:** 2026-07-07  
**Uyumlu:** Ubuntu 26+, n8n latest
