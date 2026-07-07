#!/bin/bash

################################################################################
# n8n Pre-Installation Conflict Check
# Ubuntu 26 - Mevcut uygulamalar ile çakışma kontrol
################################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
ORANGE='\033[0;33m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

log_found() {
    echo -e "${ORANGE}[!]${NC} $1"
}

# Tracker for issues
ISSUES_FOUND=0

echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  n8n Pre-Installation Compatibility Check${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo ""

# ============================================================================
# 1. PORT CHECKS
# ============================================================================
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}1. PORT KONTROL${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

CRITICAL_PORTS=(80 443 5678 5432)
DOCKER_PORTS=(5678 5432)

for port in "${CRITICAL_PORTS[@]}"; do
    if netstat -tuln 2>/dev/null | grep -q ":$port "; then
        log_found "Port $port KULLANIMDA:"
        netstat -tuln 2>/dev/null | grep ":$port " | awk '{print "    └─ " $0}'
        ISSUES_FOUND=$((ISSUES_FOUND+1))
        
        if [[ " ${DOCKER_PORTS[@]} " =~ " ${port} " ]]; then
            echo -e "    ${YELLOW}Çözüm: docker-compose.yml dosyasında farklı port belirleyin${NC}"
        else
            echo -e "    ${YELLOW}Çözüm: Mevcut servisi değiştirin veya kapatın${NC}"
        fi
    else
        log_success "Port $port - BOŞTA"
    fi
done

echo ""

# ============================================================================
# 2. DOCKER & DOCKER COMPOSE CONFLICTS
# ============================================================================
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}2. DOCKER & CONTAINER KONTROL${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check Docker installation
if command -v docker &> /dev/null; then
    log_success "Docker - YÜKLÜ"
    DOCKER_VERSION=$(docker --version)
    echo "    └─ $DOCKER_VERSION"
else
    log_warning "Docker - YÜKLİ DEĞİL (setup.sh tarafından yüklenecek)"
fi

echo ""

# Check Docker Compose
if command -v docker-compose &> /dev/null; then
    log_success "Docker Compose - YÜKLÜ"
    DC_VERSION=$(docker-compose --version)
    echo "    └─ $DC_VERSION"
else
    log_warning "Docker Compose - YÜKLİ DEĞİL (setup.sh tarafından yüklenecek)"
fi

echo ""

# Check running containers
log_info "Çalışan Container'lar:"
if [ $(docker ps -q 2>/dev/null | wc -l) -gt 0 ]; then
    docker ps --format "table {{.Names}}\t{{.Ports}}\t{{.Status}}" 2>/dev/null | tail -n +2 | while read line; do
        log_found "$line"
    done
    echo ""
    log_warning "Bu containerlar ile çakışma olabilir. Portları kontrol edin."
    ISSUES_FOUND=$((ISSUES_FOUND+1))
else
    log_success "Hiçbir container çalışmıyor"
fi

echo ""

# Check networks
log_info "Docker Networks:"
if docker network ls 2>/dev/null | grep -q "n8n-network"; then
    log_found "n8n-network zaten mevcut - silinecek mi?"
else
    log_success "n8n-network - BOŞTA (yeni oluşturulacak)"
fi

echo ""

# ============================================================================
# 3. DATABASE CONFLICTS
# ============================================================================
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}3. VERITABANI KONTROL${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check PostgreSQL
if command -v psql &> /dev/null; then
    log_found "PostgreSQL istemcisi - YÜKLÜ"
    if systemctl is-active --quiet postgresql 2>/dev/null; then
        log_found "PostgreSQL service - ÇALIŞIYOR"
        log_warning "PostgreSQL zaten host makinada çalışıyor!"
        ISSUES_FOUND=$((ISSUES_FOUND+1))
        echo "    └─ n8n containerize PostgreSQL kullanacak, çakışma yok"
        echo "    └─ Ama 5432 port'unu paylaşmamaya dikkat!"
    else
        log_success "PostgreSQL service - KAPATILMIŞ"
    fi
else
    log_success "PostgreSQL istemcisi - YÜKLİ DEĞİL"
fi

echo ""

# Check MySQL
if command -v mysql &> /dev/null; then
    log_found "MySQL istemcisi - YÜKLÜ"
    if systemctl is-active --quiet mysql 2>/dev/null; then
        log_found "MySQL service - ÇALIŞIYOR (5432 ile çakışmaz)"
        log_success "Sorun YOK - farklı port'ları kullanıyorlar"
    fi
fi

echo ""

# Check MongoDB
if command -v mongosh &> /dev/null || command -v mongo &> /dev/null; then
    log_found "MongoDB istemcisi - YÜKLÜ"
    if netstat -tuln 2>/dev/null | grep -q ":27017"; then
        log_success "MongoDB - Kendi port'unda (27017), çakışmaz"
    fi
fi

echo ""

# ============================================================================
# 4. NGINX/WEB SERVER CONFLICTS
# ============================================================================
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}4. WEB SERVER KONTROL${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check Nginx
if systemctl is-active --quiet nginx 2>/dev/null; then
    log_found "Nginx - ÇALIŞIYOR"
    ISSUES_FOUND=$((ISSUES_FOUND+1))
    echo "    └─ Port 80/443 kullanıyor"
    log_warning "ÇAKIŞMA RISKI! docker-compose.yml'de farklı port'u belirt:"
    echo "    └─ nginx: ports: ['8080:80', '8443:443']"
else
    log_success "Nginx - KAPATILMIŞ"
fi

echo ""

# Check Apache
if systemctl is-active --quiet apache2 2>/dev/null; then
    log_found "Apache - ÇALIŞIYOR"
    ISSUES_FOUND=$((ISSUES_FOUND+1))
    echo "    └─ Port 80/443 kullanıyor"
    log_warning "ÇAKIŞMA RISKI! docker-compose.yml'de farklı port'u belirt"
else
    log_success "Apache - KAPATILMIŞ"
fi

echo ""

# ============================================================================
# 5. DISK SPACE CHECK
# ============================================================================
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}5. DISK ALANI KONTROL${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
DISK_AVAILABLE=$(df -h / | awk 'NR==2 {print $4}')

echo "    Toplam Kullanım: $DISK_USAGE%"
echo "    Boş Alan: $DISK_AVAILABLE"

if [ "$DISK_USAGE" -gt 80 ]; then
    log_error "DISK DOLDU! Minimum %20 boş alan gerekli"
    ISSUES_FOUND=$((ISSUES_FOUND+1))
elif [ "$DISK_USAGE" -gt 70 ]; then
    log_warning "Disk %70 dolmuş, biraz temizleyin"
else
    log_success "Disk kullanımı normal"
fi

echo ""

# ============================================================================
# 6. MEMORY CHECK
# ============================================================================
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}6. HAFIZA KONTROL${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

FREE_MEM=$(free -h | awk 'NR==2 {print $7}')
TOTAL_MEM=$(free -h | awk 'NR==2 {print $2}')
MEM_PERCENT=$(free | awk 'NR==2 {printf("%.0f", ($3/$2)*100)}')

echo "    Toplam: $TOTAL_MEM"
echo "    Boş: $FREE_MEM"
echo "    Kullanım: $MEM_PERCENT%"

if (( $(echo "$TOTAL_MEM" | grep -oE '^[0-9]+' | head -1) < 2 )); then
    log_warning "Sadece $TOTAL_MEM RAM var! Minimum 2GB önerilir"
    ISSUES_FOUND=$((ISSUES_FOUND+1))
else
    log_success "RAM yeterli"
fi

echo ""

# ============================================================================
# 7. EXISTING APPLICATIONS
# ============================================================================
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}7. ÇALIŞAN SERVISLER${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

SERVICES=("nginx" "apache2" "mysql" "postgresql" "mongodb" "redis" "node" "python3")

for service in "${SERVICES[@]}"; do
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        log_found "$service - ÇALIŞIYOR"
    fi
done

echo ""

# ============================================================================
# SUMMARY
# ============================================================================
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  ÖZET${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
echo ""

if [ $ISSUES_FOUND -eq 0 ]; then
    echo -e "${GREEN}✓ TEMIZ! Kuruluma başlayabilirsin.${NC}"
    echo ""
    echo "Kurulum komutu:"
    echo "  sudo bash setup.sh"
    exit 0
else
    echo -e "${ORANGE}⚠ $ISSUES_FOUND ÇAKIŞMA RİSKİ BULUNDU${NC}"
    echo ""
    echo "Çözümler:"
    echo ""
    echo "1️⃣  PORT ÇAKIŞMASI:"
    echo "    • docker-compose.yml dosyasında port'u değiştir"
    echo "    • Örnek: 'ports: [\"8080:80\", \"8443:443\"]'"
    echo ""
    echo "2️⃣  WEB SERVER ÇAKIŞMASI (Nginx/Apache):"
    echo "    • Ya Nginx'i kapat: sudo systemctl stop nginx"
    echo "    • Ya docker-compose.yml'de farklı port'u kullan"
    echo ""
    echo "3️⃣  VERITABANI ÇAKIŞMASI:"
    echo "    • n8n container'ı kendi PostgreSQL'i kullanır"
    echo "    • Host'ta PostgreSQL varsa 5432 port'unu paylaştır"
    echo "    • docker-compose.yml: ports: ['5433:5432']"
    echo ""
    echo "4️⃣  DISK ALANI:"
    echo "    • docker system prune -a  (temizlik yapın)"
    echo "    • Gereksiz dosyaları silin"
    echo ""
    echo "Düzeltmeler sonrası bu scripti tekrar çalıştır."
    exit 1
fi
