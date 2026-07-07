#!/bin/bash

################################################################################
# n8n Self-Hosted Setup Script for Ubuntu 26 - FIXED
# Handles Docker Compose conflicts
################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root (use: sudo bash setup.sh)"
   exit 1
fi

log_info "Starting n8n setup for Ubuntu 26..."
log_info "This will install Docker and configure n8n"

# ============================================================================
# 1. System Update
# ============================================================================
log_info "Updating system packages..."
apt-get update
apt-get upgrade -y
apt-get install -y curl wget git vim nano htop net-tools

log_success "System packages updated"

# ============================================================================
# 2. Handle Existing Docker Installation
# ============================================================================
log_info "Checking for existing Docker installations..."

# Fix docker-compose conflict first
if dpkg -l 2>/dev/null | grep -q docker-compose-v2; then
    log_warning "docker-compose-v2 found, removing to prevent conflicts..."
    apt-get remove -y docker-compose-v2 2>/dev/null || true
    apt-get autoremove -y
fi

# Remove old Docker versions if any
apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
apt-get autoremove -y

log_success "Old Docker packages cleaned"

# ============================================================================
# 3. Install Docker
# ============================================================================
log_info "Installing Docker..."

# Install prerequisites
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release

# Add Docker GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg 2>/dev/null || true

# Add Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

log_success "Docker installed: $(docker --version)"

# ============================================================================
# 4. Install Docker Compose (Standalone)
# ============================================================================
log_info "Installing Docker Compose standalone..."

DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d'"' -f4)
log_info "Downloading Docker Compose $DOCKER_COMPOSE_VERSION..."

curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Also symlink if needed
ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose 2>/dev/null || true

log_success "Docker Compose installed: $(docker-compose --version)"

# ============================================================================
# 5. Start Docker service
# ============================================================================
log_info "Starting Docker service..."
systemctl enable docker
systemctl start docker
systemctl enable containerd

# Verify Docker is running
if systemctl is-active --quiet docker; then
    log_success "Docker service running"
else
    log_error "Docker service failed to start"
    exit 1
fi

# ============================================================================
# 6. Create n8n directory structure
# ============================================================================
log_info "Creating n8n stack directory..."

N8N_DIR="$HOME/n8n-stack"
mkdir -p "$N8N_DIR/ssl"
mkdir -p "$N8N_DIR/data"

log_success "n8n directory created at: $N8N_DIR"

# ============================================================================
# 7. SSL Certificate Setup (Self-signed for testing)
# ============================================================================
log_info "Setting up SSL certificates..."

# Ask user for SSL setup method
echo ""
echo "Select SSL certificate option:"
echo "1) Generate self-signed certificate (for testing/development)"
echo "2) Use Let's Encrypt with certbot (for production)"
echo "3) Skip SSL setup for now (HTTP only)"
read -p "Choose option [1-3]: " ssl_option

case $ssl_option in
    1)
        log_info "Generating self-signed certificate..."
        
        read -p "Enter domain name (default: localhost): " domain_name
        domain_name=${domain_name:-localhost}
        
        openssl req -x509 -newkey rsa:4096 -keyout "$N8N_DIR/ssl/key.pem" -out "$N8N_DIR/ssl/cert.pem" \
            -days 365 -nodes -subj "/C=TR/ST=Istanbul/L=Istanbul/O=n8n/CN=$domain_name"
        
        chmod 644 "$N8N_DIR/ssl/cert.pem"
        chmod 600 "$N8N_DIR/ssl/key.pem"
        
        log_success "Self-signed certificate generated"
        log_warning "⚠️  Note: Self-signed certs will show warnings in browsers. Use Let's Encrypt for production!"
        ;;
    2)
        log_info "Installing certbot..."
        apt-get install -y certbot python3-certbot-nginx
        
        read -p "Enter your domain name: " domain_name
        read -p "Enter your email address: " email_address
        
        log_info "Requesting Let's Encrypt certificate for: $domain_name"
        certbot certonly --standalone -d "$domain_name" -m "$email_address" --agree-tos --non-interactive
        
        # Copy certs to n8n directory
        cp "/etc/letsencrypt/live/$domain_name/fullchain.pem" "$N8N_DIR/ssl/cert.pem"
        cp "/etc/letsencrypt/live/$domain_name/privkey.pem" "$N8N_DIR/ssl/key.pem"
        
        log_success "Let's Encrypt certificate configured"
        ;;
    3)
        log_warning "Skipping SSL setup. n8n will run on HTTP only."
        ;;
esac

# ============================================================================
# 8. Create environment file
# ============================================================================
log_info "Creating environment configuration..."

read -p "Enter database password (or press Enter for default): " db_password
db_password=${db_password:-securepassword123}

read -p "Enter n8n domain (or press Enter for localhost): " n8n_domain
n8n_domain=${n8n_domain:-localhost}

cat > "$N8N_DIR/.env" << EOF
# Database Configuration
DB_PASSWORD=$db_password

# n8n Configuration
N8N_HOST=0.0.0.0
N8N_DOMAIN=$n8n_domain
TIMEZONE=Europe/Istanbul
N8N_PROTOCOL=https

# SSL/TLS Paths (inside Docker container)
SSL_CERT_PATH=/etc/nginx/ssl/cert.pem
SSL_KEY_PATH=/etc/nginx/ssl/key.pem

# Admin Authentication (optional)
N8N_BASIC_AUTH_ACTIVE=false

# Node environment
NODE_ENV=production
EOF

log_success "Environment file created at: $N8N_DIR/.env"

# ============================================================================
# 9. Copy configuration files from repo
# ============================================================================
log_info "Copying configuration files..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/docker-compose.yml" ]; then
    cp "$SCRIPT_DIR/docker-compose.yml" "$N8N_DIR/"
    log_success "docker-compose.yml copied"
else
    log_warning "docker-compose.yml not found in $SCRIPT_DIR, will use default"
fi

if [ -f "$SCRIPT_DIR/nginx.conf" ]; then
    cp "$SCRIPT_DIR/nginx.conf" "$N8N_DIR/"
    log_success "nginx.conf copied"
else
    log_warning "nginx.conf not found in $SCRIPT_DIR, will use default"
fi

# ============================================================================
# 10. User Group Configuration
# ============================================================================
log_info "Configuring user groups..."

if [ -n "$SUDO_USER" ]; then
    usermod -aG docker "$SUDO_USER"
    log_success "Added $SUDO_USER to docker group"
    log_info "⚠️  Log out and log back in for group changes to take effect"
fi

# ============================================================================
# 11. Display Summary
# ============================================================================
clear

cat << "EOF"
╔════════════════════════════════════════════════════════════════════════════╗
║                    n8n Setup Complete! 🎉                                 ║
╚════════════════════════════════════════════════════════════════════════════╝

EOF

echo -e "${GREEN}Installation Summary:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "✓ Docker installed: $(docker --version)"
echo -e "✓ Docker Compose installed: $(docker-compose --version)"
echo -e "✓ n8n directory created: $N8N_DIR"
echo -e "✓ SSL configured"
echo -e "✓ Environment configured"
echo ""

echo -e "${BLUE}Next Steps:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. Navigate to n8n directory:"
echo "   cd $N8N_DIR"
echo ""
echo "2. Start n8n services:"
echo "   docker-compose up -d"
echo ""
echo "3. Check status:"
echo "   docker-compose ps"
echo ""
echo "4. View logs:"
echo "   docker-compose logs -f n8n"
echo ""
echo "5. Access n8n:"
echo "   https://$n8n_domain:443  (or http://localhost:5678 without proxy)"
echo ""

echo -e "${YELLOW}Useful Commands:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "# View all services"
echo "docker-compose ps"
echo ""
echo "# View logs"
echo "docker-compose logs -f"
echo ""
echo "# Stop all services"
echo "docker-compose down"
echo ""
echo "# Restart services"
echo "docker-compose restart"
echo ""
echo "# Update to latest n8n image"
echo "docker-compose pull && docker-compose up -d"
echo ""
echo "# Access database"
echo "docker-compose exec postgres psql -U n8n -d n8n"
echo ""

echo -e "${YELLOW}Troubleshooting:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "If port 5678 is in use:"
echo "  sudo lsof -i :5678"
echo "  sudo kill -9 <PID>"
echo ""
echo "If Docker daemon won't start:"
echo "  sudo systemctl start docker"
echo "  sudo systemctl status docker"
echo ""
echo "Reset everything (warning: deletes data):"
echo "  cd $N8N_DIR"
echo "  docker-compose down -v"
echo ""

log_success "Setup completed successfully!"
