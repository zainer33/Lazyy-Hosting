#!/bin/bash
set -e

# ========== BRANDING ==========
BRAND="Lazyy Hosting"
COLOR="\e[36m"
NC="\e[0m"

# ========== ROOT CHECK ==========
if [ "$EUID" -ne 0 ]; then
  echo "❌ Run as root"
  exit 1
fi

# ========== FUNCTIONS ==========

install_dependencies() {
  apt update -y
  apt install -y curl sudo wget gnupg certbot docker.io unzip composer
  systemctl enable --now docker
}

install_panel() {
  clear
  echo -e "${COLOR}Installing Pterodactyl Panel...${NC}"

  bash <(curl -s https://raw.githubusercontent.com/pterodactyl-installer/pterodactyl-installer/master/install.sh)

  echo ""
  echo "🧑 Creating Pterodactyl Admin User"
  php /var/www/pterodactyl/artisan p:user:make
}

install_wings() {
  clear
  echo -e "${COLOR}Installing Wings...${NC}"
  bash <(curl -s https://raw.githubusercontent.com/pterodactyl-installer/pterodactyl-installer/master/install.sh) wings
}

setup_cloudflare_tunnel() {
  clear
  echo -e "${COLOR}Cloudflare Tunnel Setup${NC}"

  if ! command -v cloudflared &>/dev/null; then
    curl -fsSL https://pkg.cloudflare.com/install.sh | bash
    apt install -y cloudflared
  fi

  cloudflared tunnel login

  read -p "Tunnel name: " TUNNEL_NAME
  cloudflared tunnel create "$TUNNEL_NAME"

  TUNNEL_ID=$(cloudflared tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')

  read -p "Domain (panel.example.com): " DOMAIN
  read -p "Local panel port (80/443): " PORT

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

  echo "✅ Tunnel live at https://$DOMAIN"
}

install_reviactyl() {
  clear
  echo -e "${COLOR}Installing Reviactyl Panel Theme${NC}"

  if [ ! -f /var/www/pterodactyl/artisan ]; then
    echo "❌ Pterodactyl Panel not found!"
    echo "👉 Install Pterodactyl Panel first."
    sleep 3
    return
  fi

  echo "⚠️ This will REPLACE panel files"
  read -p "Continue? (yes/no): " confirm
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

  echo ""
  echo "✅ Reviactyl Panel installed successfully!"
}

fix_panel() {
  cd /var/www/pterodactyl
  php artisan migrate --seed --force
  php artisan queue:restart
  systemctl restart pteroq
}

# ========== MENU ==========
while true; do
  clear
  echo -e "${COLOR}"
  echo "=============================================="
  echo "   $BRAND • Pterodactyl Auto Installer"
  echo "=============================================="
  echo -e "${NC}"
  echo "1) Install Pterodactyl Panel (Admin included)"
  echo "2) Install Wings"
  echo "3) Setup Cloudflare Tunnel"
  echo "4) Install Reviactyl Panel"
  echo "5) Fix / Repair Panel"
  echo "0) Exit"
  echo ""
  read -p "Select option: " option

  case $option in
    1)
      install_dependencies
      install_panel
      ;;
    2)
      install_dependencies
      install_wings
      ;;
    3)
      setup_cloudflare_tunnel
      ;;
    4)
      install_reviactyl
      ;;
    5)
      fix_panel
      ;;
    0)
      exit
      ;;
    *)
      echo "❌ Invalid option"
      sleep 2
      ;;
  esac
done
