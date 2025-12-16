#!/bin/bash
set -e

BRAND="Lazyy Hosting"
COLOR="\e[36m"
NC="\e[0m"

if [ "$EUID" -ne 0 ]; then
  echo "❌ Run as root"
  exit 1
fi

install_dependencies() {
  apt update -y
  apt install -y curl wget sudo gnupg certbot docker.io unzip composer fail2ban iptables-persistent
  systemctl enable --now docker
  systemctl enable --now fail2ban
}

install_panel() {
  clear
  echo -e "${COLOR}Installing Pterodactyl Panel...${NC}"
  bash <(curl -s https://raw.githubusercontent.com/pterodactyl-installer/pterodactyl-installer/master/install.sh)
  echo "🧑 Creating Admin User"
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
  read -p "Local port (80/443): " PORT
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
  echo -e "${COLOR}Installing Reviactyl Panel${NC}"
  if [ ! -f /var/www/pterodactyl/artisan ]; then
    echo "❌ Pterodactyl not found! Install panel first."
    sleep 2
    return
  fi
  read -p "⚠️ This will replace panel files. Continue? (yes/no): " confirm
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
  echo "✅ Reviactyl Panel installed!"
}

enable_ddos_protection() {
  clear
  echo -e "${COLOR}Enabling DDoS Protection${NC}"
  cat <<EOF >/etc/fail2ban/jail.local
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
backend = systemd
[sshd]
enabled = true
[nginx-http-auth]
enabled = true
[nginx-limit-req]
enabled = true
[nginx-botsearch]
enabled = true
EOF
  systemctl restart fail2ban
  cat <<EOF >/etc/sysctl.d/99-ddos.conf
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.ip_local_port_range = 1024 65000
net.ipv4.tcp_tw_reuse = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
EOF
  sysctl --system
  echo "✅ DDoS Protection Enabled"
  read -p "Press Enter to return to menu..."
}

fix_panel() {
  cd /var/www/pterodactyl
  php artisan migrate --seed --force
  php artisan queue:restart
  systemctl restart pteroq
}

# ================== MENU ==================
while true; do
  clear
  echo -e "${COLOR}=============================================="
  echo "   $BRAND • Pterodactyl Auto Installer"
  echo "==============================================${NC}"
  echo "1) Install Pterodactyl Panel (Admin included)"
  echo "2) Install Wings"
  echo "3) Setup Cloudflare Tunnel"
  echo "4) Install Reviactyl Panel"
  echo "5) Enable DDoS Protection"
  echo "6) Fix / Repair Panel"
  echo "0) Exit"
  read -p "Select option: " option

  case $option in
    1) install_dependencies; install_panel ;;
    2) install_dependencies; install_wings ;;
    3) setup_cloudflare_tunnel ;;
    4) install_reviactyl ;;
    5) enable_ddos_protection ;;
    6) fix_panel ;;
    0) exit ;;
    *) echo "❌ Invalid option"; sleep 2 ;;
  esac
done
