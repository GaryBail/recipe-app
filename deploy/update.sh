#!/usr/bin/env bash
# Обновить сервер до последней версии из GitHub: сначала копия базы, потом пересборка.
set -euo pipefail
cd "$(dirname "$0")"

./backup.sh
git -C .. pull --ff-only
docker compose up -d --build
docker image prune -f >/dev/null
echo "Обновлено. Проверка: curl -fsS https://\$(grep ^DOMAIN= .env | cut -d= -f2)/health"
