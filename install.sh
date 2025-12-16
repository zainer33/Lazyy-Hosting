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
  apt install -y curl sudo wget gnupg certbot docker.io
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

  echo "🔐 Login to Cloudflare"
  cloudflared tunnel login

  read -p "Tunnel name: " TUNNEL_NAME
  cloudflared tunnel create $TUNNEL_NAME

  TUNNEL_ID=$(cloudflared tunnel list | grep "$TUNNEL_NAME" | awk '{print $1}')

  read -p "Domain (panel.example.com): " DOMAIN
  read -p "Local panel port (80/443): " PORT

  cloudflared tunnel route dns $TUNNEL_NAME $DOMAIN

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

  echo ""
  echo "✅ Tunnel live at https://$DOMAIN"
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
  echo "1) Install Panel (Admin user included)"
  echo "2) Install Wings"
  echo "3) Setup Cloudflare Tunnel (No Ports)"
  echo "4) Fix / Repair Panel"
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
