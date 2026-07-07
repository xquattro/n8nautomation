#!/bin/bash

################################################################################
# n8n Pre-Setup Docker Fix
# Removes docker-compose-v2 conflict
################################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
   log_error "Must run as root (sudo bash docker-fix.sh)"
   exit 1
fi

log_warning "Fixing Docker Compose conflicts..."

# Durdurmak gerekirse
systemctl stop docker 2>/dev/null || true

# Tüm docker-compose paketlerini kaldır
log_info "Removing conflicting packages..."
apt-get remove -y docker-compose-plugin 2>/dev/null || true
apt-get remove -y docker-compose-v2 2>/dev/null || true
apt-get remove -y docker-compose 2>/dev/null || true
apt-get autoremove -y

# Dosyaları sil
log_info "Cleaning up conflicts..."
rm -f /usr/libexec/docker/cli-plugins/docker-compose 2>/dev/null || true
rm -f /usr/bin/docker-compose 2>/dev/null || true
rm -f /usr/local/bin/docker-compose 2>/dev/null || true

# APT cache temizle
apt-get clean
rm -rf /var/cache/apt/archives/*

log_success "Docker conflicts cleaned!"

# Docker'ı başlat
log_info "Starting Docker..."
systemctl start docker
systemctl enable docker

log_success "Docker ready!"

echo ""
echo "Now run: sudo bash setup.sh"
