#!/bin/bash
#
# install-mtproxy.sh — развёртывание MTProto-прокси Telegram (alexbers/mtprotoproxy)
# на выделенном Oracle Cloud Always Free (Ubuntu 24.04, E2.1.Micro).
#
# Готовит: зависимости, код прокси в /opt/mtproto-proxy, config.py с TLS-маскировкой,
# systemd-юнит, печатает ссылки для клиентов.
#
# Запуск:  sudo bash install-mtproxy.sh
#
# Настройки (переменные окружения):
#   PORT          порт прокси (TCP+UDP), по умолчанию 8443
#   PROXY_DIR     каталог установки, по умолчанию /opt/mtproto-proxy
#   TLS_DOMAIN    домен для TLS-маскировки (проверяется при старте), по умолчанию www.google.com
#   AD_TAG        необязательный рекламный тег от @MTProxybot
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
AD_TAG="${AD_TAG:-}"

echo "== 1. Зависимости"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq git python3 python3-uvloop python3-cryptography python3-socks \
    ca-certificates xxd curl

echo "== 2. Код прокси (alexbers/mtprotoproxy) в $PROXY_DIR"
if [[ ! -d "$PROXY_DIR/.git" ]]; then
    git clone -b stable https://github.com/alexbers/mtprotoproxy.git "$PROXY_DIR"
else
    ( cd "$PROXY_DIR" && git pull -q --ff-only )
fi

echo "== 3. config.py (порт $PORT, TLS-маскировка $TLS_DOMAIN)"
SECRET="$(head -c 16 /dev/urandom | xxd -p -c 32)"
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
    echo "TLS_DOMAIN = \"$TLS_DOMAIN\""
    if [[ -n "$AD_TAG" ]]; then
        echo "AD_TAG = \"$AD_TAG\""
    fi
} > "$PROXY_DIR/config.py"
echo "   секрет записан в $PROXY_DIR/config.py (файл 600)"

echo "== 4. systemd-юнит"
sed -e "s|@PROXY_DIR@|$PROXY_DIR|g" \
    "$(dirname "$0")/deploy/mtproxy.service" > /etc/systemd/system/mtproxy.service
chmod 644 /etc/systemd/system/mtproxy.service
systemctl daemon-reload
systemctl enable --now mtproxy.service

echo "== 5. Ссылки для клиентов"
sleep 3
LINE="$(journalctl -u mtproxy -n 40 --no-pager 2>/dev/null | grep -o 'tg://proxy[^ ]*' | tail -n1 || true)"
IP="$(curl -4 -s https://ifconfig.co 2>/dev/null || echo 'ВАШ_ПУБЛИЧНЫЙ_IP')"
if [[ -n "$LINE" ]]; then
    echo "  tg://  $LINE"
    echo "  web:   https://t.me/proxy?server=$IP&port=$PORT&secret=${LINE#tg://proxy?server=*&secret=}"
    echo "         (если строка выше пустая — скопируйте secret из лога командой ниже)"
else
    echo "  ссылку читайте из лога:"
    echo "    journalctl -u mtproxy -n 50 --no-pager | grep -o 'tg://proxy[^ ]*'"
fi

echo "=="
echo "Готово. Дальше:"
echo "  1) Oracle → Security List сервера: открыть порт $PORT (TCP и UDP) для 0.0.0.0/0"
echo "  2) Раздать ссылку (кнопка в клиенте Telegram: 'Подключить прокси')"
echo "  3) Проверка: journalctl -u mtproxy -f"
echo "  4) Смена секрета/ссылки: rm -f $PROXY_DIR/config.py && sudo bash $0"