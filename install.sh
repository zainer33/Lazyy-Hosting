#!/bin/bash

clear
echo -e "\e[36m"
echo "=============================================="
echo "      Lazyy Hosting • Pterodactyl Installer"
echo "=============================================="
echo -e "\e[0m"

if [ "$EUID" -ne 0 ]; then
  echo "❌ Run as root"
  exit 1
fi

echo ""
echo "1) Install Pterodactyl Panel"
echo "2) Install Wings"
echo "3) Setup Domain + SSL"
echo "4) Create Admin User"
echo "5) Fix / Repair Panel"
echo "6) Uninstall Everything"
echo "0) Exit"
echo ""
read -p "Select option: " option

case $option in
1)
  bash <(curl -s https://raw.githubusercontent.com/pterodactyl-installer/pterodactyl-installer/master/install.sh)
  ;;
2)
  bash <(curl -s https://raw.githubusercontent.com/pterodactyl-installer/pterodactyl-installer/master/install.sh) wings
  ;;
3)
  read -p "Enter domain (panel.example.com): " DOMAIN
  certbot --nginx -d $DOMAIN
  ;;
4)
  php /var/www/pterodactyl/artisan p:user:make
  ;;
5)
  cd /var/www/pterodactyl || exit
  php artisan migrate --seed --force
  php artisan queue:restart
  systemctl restart pteroq
  ;;
6)
  read -p "Are you sure? (yes/no): " confirm
  if [ "$confirm" = "yes" ]; then
    rm -rf /var/www/pterodactyl
    docker rm -f $(docker ps -aq)
    docker system prune -af
  fi
  ;;
0)
  exit
  ;;
*)
  echo "❌ Invalid option"
  ;;
esac
