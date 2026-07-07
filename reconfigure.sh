#!/bin/bash

################################################################################
# n8n Reconfigure for Public IP
# Updates SSL certificate and configuration for public IP access
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
   log_error "Must run as root (sudo bash reconfigure.sh)"
   exit 1
fi

N8N_DIR="/root/n8n-stack"
PUBLIC_IP="${1:-}"

if [ -z "$PUBLIC_IP" ]; then
    log_error "Please provide Public IP as argument"
    echo "Usage: sudo bash reconfigure.sh <PUBLIC_IP>"
    echo "Example: sudo bash reconfigure.sh 204.168.255.122"
    exit 1
fi

log_info "Reconfiguring n8n for Public IP: $PUBLIC_IP"

# ============================================================================
# 1. Stop services
# ============================================================================
log_info "Stopping services..."
cd "$N8N_DIR"
docker-compose down

# ============================================================================
# 2. Generate new SSL certificate for Public IP
# ============================================================================
log_info "Generating SSL certificate for $PUBLIC_IP..."

openssl req -x509 -newkey rsa:4096 \
    -keyout "$N8N_DIR/ssl/key.pem" \
    -out "$N8N_DIR/ssl/cert.pem" \
    -days 365 -nodes \
    -subj "/C=TR/ST=Istanbul/L=Istanbul/O=n8n/CN=$PUBLIC_IP" \
    -addext "subjectAltName=IP:$PUBLIC_IP"

chmod 644 "$N8N_DIR/ssl/cert.pem"
chmod 600 "$N8N_DIR/ssl/key.pem"

log_success "SSL certificate generated for $PUBLIC_IP"

# ============================================================================
# 3. Update .env file
# ============================================================================
log_info "Updating .env configuration..."

# Read current values
DB_PASSWORD=$(grep "^DB_PASSWORD=" "$N8N_DIR/.env" | cut -d'=' -f2)
TIMEZONE=$(grep "^TIMEZONE=" "$N8N_DIR/.env" | cut -d'=' -f2)

cat > "$N8N_DIR/.env" << EOF
# Database Configuration
DB_PASSWORD=$DB_PASSWORD

# n8n Configuration
N8N_HOST=0.0.0.0
N8N_DOMAIN=$PUBLIC_IP
TIMEZONE=$TIMEZONE
N8N_PROTOCOL=https

# SSL/TLS Paths (inside Docker container)
SSL_CERT_PATH=/etc/nginx/ssl/cert.pem
SSL_KEY_PATH=/etc/nginx/ssl/key.pem

# Admin Authentication (optional)
N8N_BASIC_AUTH_ACTIVE=false

# Node environment
NODE_ENV=production
EOF

log_success ".env updated with Public IP"

# ============================================================================
# 4. Update docker-compose.yml
# ============================================================================
log_info "Updating docker-compose.yml..."

# Check if docker-compose.yml exists, if not create it
if [ ! -f "$N8N_DIR/docker-compose.yml" ]; then
    log_warning "docker-compose.yml not found, creating default..."
    cat > "$N8N_DIR/docker-compose.yml" << 'COMPOSE_EOF'
version: '3.8'

services:
  postgres:
    image: postgres:15-alpine
    container_name: n8n-postgres
    environment:
      POSTGRES_USER: n8n
      POSTGRES_PASSWORD: ${DB_PASSWORD:-securepassword123}
      POSTGRES_DB: n8n
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U n8n"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - n8n-network
    restart: unless-stopped

  n8n:
    image: n8nio/n8n:latest
    container_name: n8n-main
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=n8n
      - DB_POSTGRESDB_PASSWORD=${DB_PASSWORD:-securepassword123}
      - N8N_HOST=${N8N_HOST:-0.0.0.0}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - NODE_ENV=production
      - WEBHOOK_URL=https://${N8N_DOMAIN}
      - GENERIC_TIMEZONE=${TIMEZONE:-UTC}
    ports:
      - "5678:5678"
    volumes:
      - n8n_data:/home/node/.n8n
    networks:
      - n8n-network
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5678/healthz"]
      interval: 30s
      timeout: 10s
      retries: 3

  nginx:
    image: nginx:alpine
    container_name: n8n-nginx
    depends_on:
      - n8n
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - ./ssl:/etc/nginx/ssl:ro
      - nginx_logs:/var/log/nginx
    networks:
      - n8n-network
    restart: unless-stopped

volumes:
  postgres_data:
  n8n_data:
  nginx_logs:

networks:
  n8n-network:
    driver: bridge
COMPOSE_EOF
fi

log_success "docker-compose.yml configured"

# ============================================================================
# 5. Update nginx.conf
# ============================================================================
log_info "Updating nginx.conf for $PUBLIC_IP..."

cat > "$N8N_DIR/nginx.conf" << 'NGINX_EOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    client_max_body_size 100M;

    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml text/javascript 
               application/json application/javascript application/xml+rss;

    server {
        listen 80;
        server_name _;
        location / {
            return 301 https://$host$request_uri;
        }
    }

    server {
        listen 443 ssl http2;
        server_name _;

        ssl_certificate /etc/nginx/ssl/cert.pem;
        ssl_certificate_key /etc/nginx/ssl/key.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5;
        ssl_prefer_server_ciphers on;
        ssl_session_cache shared:SSL:10m;
        ssl_session_timeout 10m;

        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header Referrer-Policy "no-referrer-when-downgrade" always;

        location / {
            proxy_pass http://n8n:5678;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_cache_bypass $http_upgrade;
            proxy_read_timeout 600s;
            proxy_connect_timeout 600s;
            proxy_send_timeout 600s;
        }

        location /webhook/ {
            proxy_pass http://n8n:5678;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }
}
NGINX_EOF

log_success "nginx.conf updated"

# ============================================================================
# 6. Start services again
# ============================================================================
log_info "Starting services with new configuration..."
docker-compose up -d

log_success "Services started!"

# ============================================================================
# 7. Display Summary
# ============================================================================
clear

cat << "EOF"
╔════════════════════════════════════════════════════════════════════════════╗
║                    n8n Reconfigured! 🎉                                   ║
╚════════════════════════════════════════════════════════════════════════════╝

EOF

echo -e "${GREEN}Reconfiguration Summary:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "✓ SSL certificate updated for: $PUBLIC_IP"
echo -e "✓ .env configuration updated"
echo -e "✓ docker-compose.yml configured"
echo -e "✓ nginx.conf updated"
echo -e "✓ Services restarted"
echo ""

echo -e "${BLUE}Access n8n:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "URL: https://$PUBLIC_IP"
echo ""
echo -e "${YELLOW}Note:${NC} Self-signed certificate will show browser warning"
echo "      This is normal. Click 'Advanced' → 'Proceed'"
echo ""

echo -e "${BLUE}Next Steps:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. Check service status:"
echo "   docker-compose ps"
echo ""
echo "2. View logs:"
echo "   docker-compose logs -f n8n"
echo ""
echo "3. Wait 30-60 seconds for services to fully start"
echo ""
echo "4. Open browser and go to:"
echo "   https://$PUBLIC_IP"
echo ""

log_success "Reconfiguration completed!"
