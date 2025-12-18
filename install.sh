#!/bin/bash
set -e

# ================== CONFIG ==================
BRAND="Lazyy Hosting Manager"
COLOR="\e[36m"
NC="\e[0m"

# ================== ROOT CHECK ==================
if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run as root"
  exit 1
fi

# ================== DEPENDENCIES (FIXED) ==================
install_dependencies() {
  echo "▶ Installing system dependencies..."
  apt update -y

  # Remove conflicting docker/containerd packages
  apt remove -y \
    containerd \
    docker \
    docker-engine \
    docker.io \
    docker-ce \
    docker-ce-cli || true

  apt autoremove -y

  # Base packages
  apt install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    unzip \
    sudo \
    composer

  # Install Docker safely (official method)
  curl -fsSL https://get.docker.com | bash

  systemctl enable --now docker
  echo "✅ Dependencies installed"
}

# ================== PANEL INSTALL ==================
install_panel() {
  clear
  echo -e "${COLOR}▶ Pterodactyl Panel Installer${NC}"

  read -p "Enter Panel Domain or IPv4: " PANEL_DOMAIN

  bash <(curl -s https://raw.githubusercontent.com/pterodactyl-installer/pterodactyl-installer/master/install.sh)

  echo ""
  echo "▶ Creating Admin User"
  php /var/www/pterodactyl/artisan p:user:make

  echo ""
  echo "✅ Panel Installed Successfully"
  echo "🌐 Panel URL: https://$PANEL_DOMAIN"
  read -p "Press Enter to continue..."
}

# ================== CLOUDFARE TUNNEL ==================
setup_cloudflare_tunnel() {
  clear
  echo -e "${COLOR}▶ Cloudflare Tunnel Setup${NC}"

  if ! command -v cloudflared &>/dev/null; then
    curl -fsSL https://pkg.cloudflare.com/install.sh | bash
    apt install -y cloudflared
  fi

  cloudflared tunnel login
  read -p "Tunnel Name: " TUNNEL_NAME
  cloudflared tunnel create "$TUNNEL_NAME"

  TUNNEL_ID=$(cloudflared tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')

  read -p "Domain (panel.example.com): " DOMAIN
  read -p "Local Port (80 or 443): " PORT

  cloudflared tunnel route dns "$TUNNEL_NAME" "$DOMAIN"

  mkdir -p /etc/cloudflared
  cat <<EOF >/etc/cloudflared/config.yml
tunnel: $TUNNEL_ID
credentials-file: /root/.cloudflared/$TUNNEL_ID.json
ingress:
  - hostname: $DOMAIN
    service: http://localhost:$PORT
  - service: http_status:404
EOF

  cloudflared service install
  systemctl restart cloudflared

  echo "✅ Cloudflare Tunnel Active at https://$DOMAIN"
  read -p "Press Enter to continue..."
}

# ================== REVIACTYL PANEL ==================
install_reviactyl() {
  clear
  echo -e "${COLOR}▶ Reviactyl Panel Installer${NC}"

  if [ ! -f /var/www/pterodactyl/artisan ]; then
    echo "❌ Pterodactyl Panel not installed"
    sleep 2
    return
  fi

  read -p "⚠️ Replace existing panel files? (yes/no): " confirm
  [ "$confirm" != "yes" ] && return

  cd /var/www/pterodactyl
  rm -rf *

  curl -Lo panel.tar.gz https://github.com/reviactyl/panel/releases/latest/download/panel.tar.gz
  tar -xzvf panel.tar.gz
  rm panel.tar.gz

  chmod -R 755 storage/* bootstrap/cache/
  COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader
  php artisan migrate --seed --force
  chown -R www-data:www-data /var/www/pterodactyl/*
  systemctl restart pteroq.service

  echo "✅ Reviactyl Panel Installed"
  read -p "Press Enter to continue..."
}

# ================== PANEL FIX ==================
fix_panel() {
  clear
  echo -e "${COLOR}▶ Fixing Panel${NC}"

  cd /var/www/pterodactyl
  php artisan migrate --seed --force
  php artisan queue:restart
  systemctl restart pteroq

  echo "✅ Panel Fixed"
  read -p "Press Enter to continue..."
}

# ================== MENU ==================
while true; do
  clear
  echo -e "${COLOR}=============================================="
  echo "   $BRAND"
  echo "==============================================${NC}"
  echo "1) Install Pterodactyl Panel"
  echo "2) Install Panel with Custom IPv4 / Domain"
  echo "3) Setup Cloudflare Tunnel"
  echo "4) Install Reviactyl Panel"
  echo "5) Fix / Repair Panel"
  echo "0) Exit"
  echo "----------------------------------------------"
  read -p "Select an option: " option

  case $option in
    1) install_dependencies; install_panel ;;
    2) install_dependencies; install_panel ;;
    3) setup_cloudflare_tunnel ;;
    4) install_reviactyl ;;
    5) fix_panel ;;
    0) exit ;;
    *) echo "❌ Invalid option"; sleep 2 ;;
  esac
done
