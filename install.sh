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

PTERO_DIR="/var/www/pterodactyl"

# ================== DEPENDENCIES ==================
install_dependencies() {
  echo "▶ Installing system dependencies..."
  apt update -y

  apt remove -y \
    containerd \
    docker \
    docker-engine \
    docker.io \
    docker-ce \
    docker-ce-cli || true

  apt autoremove -y

  apt install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    unzip \
    sudo \
    composer \
    git

  curl -fsSL https://get.docker.com | bash
  systemctl enable --now docker

  echo "✅ Dependencies installed"
}

# ================== CHECK PANEL ==================
check_panel() {
  if [ ! -f "$PTERO_DIR/artisan" ]; then
    echo "❌ Pterodactyl panel not found at $PTERO_DIR"
    echo "👉 Install Pterodactyl panel first"
    sleep 3
    return 1
  fi
  return 0
}

# ================== UNINSTALL THEME ==================
uninstall_theme() {
  clear
  echo -e "${COLOR}▶ Uninstall Custom Theme${NC}"

  check_panel || return

  read -p "⚠️ This will restore DEFAULT Pterodactyl theme. Continue? (yes/no): " confirm
  [ "$confirm" != "yes" ] && return

  cd $PTERO_DIR

  echo "▶ Re-downloading official panel files..."
  curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
  tar -xzvf panel.tar.gz
  rm panel.tar.gz

  chmod -R 755 storage/* bootstrap/cache/
  COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader
  php artisan migrate --seed --force
  chown -R www-data:www-data $PTERO_DIR/*
  systemctl restart pteroq.service

  echo "✅ Theme removed, default panel restored"
  read -p "Press Enter to continue..."
}

# ================== INSTALL BLUEPRINT ==================
install_blueprint() {
  clear
  echo -e "${COLOR}▶ Install Pterodactyl Blueprint${NC}"

  check_panel || return

  cd $PTERO_DIR

  if [ -d "blueprint" ]; then
    echo "ℹ️ Blueprint already installed"
    sleep 2
    return
  fi

  echo "▶ Installing Blueprint..."
  git clone https://github.com/BlueprintFramework/framework.git blueprint

  cd blueprint
  chmod +x blueprint.sh
  ./blueprint.sh install

  echo "▶ Finalizing..."
  php $PTERO_DIR/artisan optimize:clear
  systemctl restart pteroq.service

  echo "✅ Blueprint installed successfully"
  read -p "Press Enter to continue..."
}

# ================== CLOUDFLARE TUNNEL ==================
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
  read -p "Local Port (80/443): " PORT

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

  echo "✅ Cloudflare Tunnel active"
  read -p "Press Enter to continue..."
}

# ================== PANEL FIX ==================
fix_panel() {
  clear
  echo -e "${COLOR}▶ Fix / Repair Panel${NC}"

  check_panel || return

  cd $PTERO_DIR
  php artisan migrate --seed --force
  php artisan optimize:clear
  php artisan queue:restart
  systemctl restart pteroq

  echo "✅ Panel fixed"
  read -p "Press Enter to continue..."
}

# ================== MENU ==================
while true; do
  clear
  echo -e "${COLOR}=============================================="
  echo "   $BRAND"
  echo "==============================================${NC}"
  echo "1) Install Dependencies"
  echo "2) Uninstall Theme (Restore Default)"
  echo "3) Install Blueprint"
  echo "4) Setup Cloudflare Tunnel"
  echo "5) Fix / Repair Panel"
  echo "0) Exit"
  echo "----------------------------------------------"
  read -p "Select an option: " option

  case $option in
    1) install_dependencies ;;
    2) uninstall_theme ;;
    3) install_blueprint ;;
    4) setup_cloudflare_tunnel ;;
    5) fix_panel ;;
    0) exit ;;
    *) echo "❌ Invalid option"; sleep 2 ;;
  esac
done
