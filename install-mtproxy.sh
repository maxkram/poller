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

# Определяем семейство ОС (Ubuntu/Debian vs Oracle Linux)
if command -v dnf >/dev/null 2>&1; then
    OS_FAMILY="oracle"
    INSTALL="dnf install -y"
else
    OS_FAMILY="debian"
    INSTALL="apt-get install -y -qq"
fi

echo "== 1. Зависимости (${OS_FAMILY})"
export DEBIAN_FRONTEND=noninteractive
if [[ "$OS_FAMILY" == "debian" ]]; then
    apt-get update -qq
fi
# Минимальный набор: ставим только недостающее (экономия RAM на малых инстансах,
# где dnf падает по OOM). git НЕ нужен — исходники берём tarball'ом (шаг 2).
if ! command -v curl >/dev/null 2>&1; then
    $INSTALL curl
fi
if ! python3 -c 'import cryptography' 2>/dev/null; then
    $INSTALL python3-cryptography
fi
echo "   curl / python3 / cryptography готовы; опциональные (uvloop/socks) пропускаем"

echo "== 2. Код прокси (alexbers/mtprotoproxy) в $PROXY_DIR"
mkdir -p "$PROXY_DIR"
TMP_TG="$(mktemp)"
if curl -fsSL -o "$TMP_TG" https://github.com/alexbers/mtprotoproxy/archive/refs/heads/stable.tar.gz 2>/dev/null; then
    echo "   загружен stable"
else
    curl -fsSL -o "$TMP_TG" https://github.com/alexbers/mtprotoproxy/archive/refs/heads/master.tar.gz
    echo "   загружен master"
fi
tar xzf "$TMP_TG" -C "$PROXY_DIR" --strip-components=1
rm -f "$TMP_TG"
[ -f "$PROXY_DIR/mtprotoproxy.py" ] || { echo "не нашёл mtprotoproxy.py после загрузки" >&2; exit 1; }

echo "== 3. config.py (порт $PORT, TLS-маскировка $TLS_DOMAIN)"
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

echo "== 5. Открытие порта $PORT на хосте (firewalld для Oracle Linux)"
if [[ "$OS_FAMILY" == "oracle" ]]; then
    firewall-cmd --permanent --add-port="$PORT/tcp" --add-port="$PORT/udp"
    firewall-cmd --reload
    echo "   firewalld: открыты $PORT/tcp и $PORT/udp"
else
    echo "   Ubuntu: порты открываются в Security List Oracle (см. ниже)"
fi

echo "== 6. Ссылки для клиентов"
sleep 3
LINE="$(journalctl -u mtproxy -n 40 --no-pager 2>/dev/null | grep -o 'tg://proxy[^ ]*' | tail -n1 || true)"
IP="$(curl -4 -s https://ifconfig.co 2>/dev/null || echo 'ВАШ_ПУБЛИЧНЫЙ_IP')"
if [[ -n "$LINE" ]]; then
    SECRET="${LINE##*&secret=}"
    echo "  tg://  $LINE"
    echo "  web:   https://t.me/proxy?server=$IP&port=$PORT&secret=$SECRET"
    echo "         (кнопка в Telegram: 'Подключить прокси', либо просто открыть ссылку)"
else
    echo "  ссылку читайте из лога:"
    echo "    journalctl -u mtproxy -n 50 --no-pager | grep -o 'tg://proxy[^ ]*'"
fi

echo "=="
echo "Готово. Дальше:"
echo "  1) Oracle → Security List (вашего инстанса) открыть порт $PORT TCP и UDP для 0.0.0.0/0"
echo "     (внешний вход; firewalld на хосте уже открыт скриптом)"
echo "  2) Раздать ссылку (кнопка в клиенте Telegram: 'Подключить прокси')"
echo "  3) Проверка: journalctl -u mtproxy -f"
echo "  4) Смена секрета/ссылки: rm -f $PROXY_DIR/config.py && sudo bash $0"