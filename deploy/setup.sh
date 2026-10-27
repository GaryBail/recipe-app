#!/usr/bin/env bash
# Первичная установка на чистый сервер Ubuntu 22.04/24.04. Запускать от root:
#   curl -fsSL https://raw.githubusercontent.com/GaryBail/recipe-app/main/deploy/setup.sh | bash -s -- api.example.ru
# Аргумент — домен, уже направленный на IP этого сервера.
set -euo pipefail

DOMAIN="${1:-}"
REPO="https://github.com/GaryBail/recipe-app.git"
DIR="/opt/recipe-app"

if [[ $EUID -ne 0 ]]; then
  echo "Запустите от root (или через sudo)." >&2
  exit 1
fi
if [[ -z "$DOMAIN" ]]; then
  echo "Укажите домен: bash setup.sh api.example.ru" >&2
  exit 1
fi

echo "==> Обновление системы и базовые пакеты"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get upgrade -y -q
apt-get install -y -q git curl ufw unattended-upgrades dnsutils
dpkg-reconfigure -f noninteractive unattended-upgrades   # автоматические обновления безопасности

echo "==> Файл подкачки (браузеру нужна память)"
if ! swapon --show | grep -q .; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo "/swapfile none swap sw 0 0" >> /etc/fstab
fi

echo "==> Docker"
if ! command -v docker >/dev/null; then
  curl -fsSL https://get.docker.com | sh
fi
systemctl enable --now docker

echo "==> Файрвол: открыты только SSH, HTTP и HTTPS"
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

echo "==> Код приложения"
if [[ -d "$DIR/.git" ]]; then
  git -C "$DIR" pull --ff-only
else
  git clone --depth 1 "$REPO" "$DIR"
fi
cd "$DIR/deploy"
mkdir -p data/backups secrets
chown -R 1000:1000 data   # пользователь app внутри контейнера

if [[ ! -f .env ]]; then
  cp .env.example .env
  sed -i "s/^DOMAIN=.*/DOMAIN=${DOMAIN}/" .env
  chmod 600 .env
fi

echo "==> Проверка домена"
SERVER_IP=$(curl -fsS https://api.ipify.org || true)
DOMAIN_IP=$(dig +short "$DOMAIN" A | tail -n1 || true)
if [[ -n "$SERVER_IP" && "$SERVER_IP" != "$DOMAIN_IP" ]]; then
  echo "ВНИМАНИЕ: $DOMAIN указывает на '${DOMAIN_IP:-ничего}', а IP сервера — $SERVER_IP."
  echo "HTTPS-сертификат не выдадут, пока A-запись домена не станет $SERVER_IP (обновление DNS может занять до часа)."
fi

echo "==> Сборка и запуск (первый раз — 5–10 минут: скачивается браузер)"
docker compose up -d --build

echo "==> Ежедневная резервная копия базы в 03:30"
cat > /etc/cron.d/recipe-app-backup <<EOF
30 3 * * * root $DIR/deploy/backup.sh >> /var/log/recipe-app-backup.log 2>&1
EOF
chmod +x "$DIR/deploy/backup.sh" "$DIR/deploy/update.sh"

echo
echo "Готово. Через минуту проверьте: https://$DOMAIN/health — должно быть {\"ok\":true}"
echo "Адрес для приложения (⚙️ → Сервер): https://$DOMAIN"
echo "Настройки почты и push: nano $DIR/deploy/.env, затем: cd $DIR/deploy && docker compose up -d"
