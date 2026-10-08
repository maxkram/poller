#!/bin/bash
#
# mtproxy-links.sh — показать ссылки MTProto-прокси с сервера.
# Работает на сервере (где стоит прокси).
#
#   sudo bash mtproxy-links.sh            # показать текущую ссылку
#   sudo bash mtproxy-links.sh --regen     # сменить секрет (перезаписать config.py) и перезапустить
#
# Окружение:
#   PORT / PROXY_DIR / TLS_DOMAIN — те же, что у install-mtproxy.sh
# ---------------------------------------------------------------------------

set -euo pipefail
: "${HOME:=/root}"
if [[ $EUID -ne 0 ]]; then
    echo "Запустите с sudo" >&2
    exit 1
fi

PORT="${PORT:-8443}"
PROXY_DIR="${PROXY_DIR:-/opt/mtproto-proxy}"
TLS_DOMAIN="${TLS_DOMAIN:-www.google.com}"

if [[ "${1:-}" == "--regen" ]]; then
    # Сохранить текущий домен/тег, сменить секрет, перезаписать config.py целиком
    OLD_DOMAIN="$(sed -n 's/TLS_DOMAIN = "\(.*\)"/\1/p' "$PROXY_DIR/config.py" | head -n1)"
    OLD_TAG="$(sed -n 's/AD_TAG = "\(.*\)"/\1/p' "$PROXY_DIR/config.py" | head -n1)"
    SECRET="$(python3 -c 'import secrets;print(secrets.token_hex(16))')"
    {
        echo "PORT = $PORT"
        echo
        echo "# name -> secret (32 hex chars)"
        echo "USERS = {"
        echo "    \"tg\":  \"$SECRET\","
        echo "}"
        echo
        echo "MODES = {"
        echo "    \"classic\": False,"
        echo "    \"secure\": False,"
        echo "    \"tls\": True"
        echo "}"
        echo
        echo "# Домен для TLS-маскировки, проверяется при старте"
        echo "TLS_DOMAIN = \"${OLD_DOMAIN:-$TLS_DOMAIN}\""
        if [[ -n "$OLD_TAG" ]]; then
            echo "AD_TAG = \"$OLD_TAG\""
        fi
    } > "$PROXY_DIR/config.py"
    echo "Секрет сменён, перезапуск..."
    systemctl restart mtproxy
    sleep 3
else
    SECRET="$(sed -n 's/.*"\([0-9a-f]\{32\}\)".*/\1/p' "$PROXY_DIR/config.py" | head -n1)"
fi

# Точный формат (с префиксом ee/dd) — в логе прокси
LINE="$(journalctl -u mtproxy -n 60 --no-pager 2>/dev/null | grep -o 'tg://proxy[^ ]*' | tail -n1 || true)"
IP="$(curl -4 -s https://ifconfig.co 2>/dev/null || echo 'ВАШ_ПУБЛИЧНЫЙ_IP')"

echo "IP:   $IP"
echo "Порт: $PORT (TCP+UDP; откройте в Security List Oracle)"
if [[ -n "$LINE" ]]; then
    echo "tg:// $LINE"
    echo "web:  https://t.me/proxy?server=$IP&port=$PORT&secret=${LINE##*&secret=}"
else
    echo "Точный secret (с префиксом ee/dd): смотрите в"
    echo "  journalctl -u mtproxy -n 60 --no-pager | grep 'secret'"
    echo "Либо (TLS-форма, префикс dd):"
    echo "  https://t.me/proxy?server=$IP&port=$PORT&secret=dd$SECRET$TLS_DOMAIN"
fi