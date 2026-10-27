#!/usr/bin/env bash
# Резервная копия базы (аккаунты, сообщество, подписки). Хранятся последние 14 копий.
# Восстановление: остановить api, скопировать нужный файл в data/community.db, запустить api.
set -euo pipefail
cd "$(dirname "$0")"

STAMP=$(date +%Y-%m-%d_%H%M)
# Онлайн-копия средствами SQLite: безопасно, даже если сервер в этот момент пишет в базу.
docker compose exec -T api python -c "
import sqlite3
src = sqlite3.connect('/data/community.db')
dst = sqlite3.connect('/data/backups/community-${STAMP}.db')
src.backup(dst)
dst.close(); src.close()
"
gzip -f "data/backups/community-${STAMP}.db"
ls -1t data/backups/community-*.db.gz | tail -n +15 | xargs -r rm --
echo "$(date '+%F %T') backup ok: community-${STAMP}.db.gz"
