#!/bin/bash
# ---------------------------------------------------------------------------
# Развёртывание peer_poller на сервере (Debian/Ubuntu, запуск с sudo/root):
#   из каталога, где лежат peer_poller.sh, peers.txt и deploy/:
#     scp install-server.sh peer_poller.sh peers.txt root@SERVER:/tmp/ \
#       && scp -r deploy root@SERVER:/tmp/ \
#       && ssh root@SERVER 'cd /tmp && sudo bash install-server.sh'
#
# После установки заполните /opt/peer-poller/.env (S21_*, TG_*) и проверьте:
#     /opt/peer-poller/peer_poller.sh --test-tg
# ---------------------------------------------------------------------------

set -euo pipefail

BASE=/opt/peer-poller
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $EUID -ne 0 ]]; then
    echo "Запустите с sudo" >&2
    exit 1
fi

for f in peer_poller.sh peers.txt deploy/peer-poller.service deploy/peer-poller.timer \
         deploy/peer-poller-web.service; do
    [[ -f "$SRC_DIR/$f" ]] || { echo "Не найден файл: $SRC_DIR/$f" >&2; exit 1; }
done
[[ -f "$SRC_DIR/peers_web.py" ]] || { echo "Не найден файл: $SRC_DIR/peers_web.py" >&2; exit 1; }

echo "== 1. Зависимости (jq, curl, ca-certificates, python3)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq jq curl ca-certificates python3

echo "== 2. Файлы в $BASE"
mkdir -p "$BASE/state"
install -m 755 "$SRC_DIR/peer_poller.sh" "$BASE/peer_poller.sh"
install -m 644 "$SRC_DIR/peers.txt" "$BASE/peers.txt"
install -m 644 "$SRC_DIR/peers_web.py" "$BASE/peers_web.py"

if [[ ! -f "$BASE/.env" ]]; then
    cat > "$BASE/.env" <<'EOF'
# Учётная запись 21-school (для токена API)
S21_USERNAME=
S21_PASSWORD=

# Telegram-бот: токен от @BotFather и ваш chat_id
# (chat_id узнать: отправить сообщение @userinfobot)
TG_BOT_TOKEN=
TG_CHAT_ID=
EOF
    install -m 600 "$BASE/.env" "$BASE/.env"
    echo "   создан шаблон $BASE/.env — ЗАПОЛНИТЕ ИХ"
fi

echo "== 3. systemd (системные юниты)"
install -m 644 "$SRC_DIR/deploy/peer-poller.service" /etc/systemd/system/peer-poller.service
install -m 644 "$SRC_DIR/deploy/peer-poller.timer" /etc/systemd/system/peer-poller.timer
install -m 644 "$SRC_DIR/deploy/peer-poller-web.service" /etc/systemd/system/peer-poller-web.service
systemctl daemon-reload
systemctl enable --now peer-poller.timer
systemctl enable --now peer-poller-web.service

echo "== 4. Web UI"
if [[ ! -f "$BASE/web_token" ]]; then
    python3 -c "import secrets; print(secrets.token_urlsafe(16))" > "$BASE/web_token"
    chmod 600 "$BASE/web_token"
fi

echo "=="
echo "Готово. Дальше:"
echo "  1) nano /opt/peer-poller/.env      # заполнить S21_USERNAME/PASSWORD, TG_BOT_TOKEN, TG_CHAT_ID"
echo "  2) /opt/peer-poller/peer_poller.sh --test-tg   # проверка Telegram"
echo "  3) /opt/peer-poller/peer_poller.sh --once      # первый снимок (baseline)"
echo "  4) Web UI: http://<IP-сервера>:8080/p/$(cat "$BASE/web_token")"
echo "  5) journalctl -u peer-poller -f               # лог"