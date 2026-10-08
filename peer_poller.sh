#!/bin/bash
#
# ---------------------------------------------------------------------------
# peer_poller.sh — мониторинг статусов проектов списка пиров (21-school).
#
# Для каждого логина из PEERS_FILE снимается полный список проектов
# (/participants/{login}/projects) и сравнивается с предыдущим снимком.
# Изменения (смена статуса, новые проекты, исчезнувшие) пишутся в
# state/peers_history.log и на stdout.
#
# Примеры запуска:
# ./peer_poller.sh                 # один цикл (для systemd timer / cron)
# ./peer_poller.sh --loop          # постоянный запуск (демон), интервал POLL_INTERVAL
# ./peer_poller.sh --show          # текущие «живые» проекты пиров (IN_PROGRESS/IN_REVIEWS/ACCEPTED)
# ./peer_poller.sh --reset         # сбросить базовый снимок (первая полная перезапись state)
#
# Настройки через переменные окружения:
#   PEERS_FILE        файл с логинами (по умолчанию <скрипт>/peers.txt)
#   STATE_DIR         каталог состояния (по умолчанию <скрипт>/state)
#   POLL_INTERVAL     секунды между циклами в режиме --loop (по умолчанию 600)
#   S21_USERNAME/S21_PASSWORD  либо в <скрипт>/.env, либо в ~/.env, либо в окружении
# ---------------------------------------------------------------------------

set -euo pipefail
: "${HOME:=/root}"   # systemd не передаёт HOME в системных юнитах; без этого set -u падает

AUTH_URL="https://auth.21-school.ru/auth/realms/EduPowerKeycloak/protocol/openid-connect/token"
BASE_URL="https://platform.21-school.ru/services/21-school/api/v1"
CLIENT_ID="s21-open-api"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOKEN_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/s21"
TOKEN_CACHE_FILE="$TOKEN_CACHE_DIR/token.json"

PEERS_FILE="${PEERS_FILE:-$SCRIPT_DIR/peers.txt}"
STATE_DIR="${STATE_DIR:-$SCRIPT_DIR/state}"
STATE_FILE="$STATE_DIR/peers_state.tsv"
HISTORY_FILE="$STATE_DIR/peers_history.log"
POLL_INTERVAL="${POLL_INTERVAL:-600}"

# Telegram-уведомления (задаются в .env или окружении; без токена уведомления отключены)
TG_BOT_TOKEN="${TG_BOT_TOKEN:-}"
TG_CHAT_ID="${TG_CHAT_ID:-}"

PAGE_SIZE=500
CURL_TIMEOUT=30
API_RETRIES=1

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

TMP_FILES=()

new_tmp() {
    local target="$1" f
    f=$(mktemp) || die "Не удалось создать временный файл (mktemp)"
    TMP_FILES+=("$f")
    printf -v "$target" '%s' "$f"
}

cleanup() {
    if (( ${#TMP_FILES[@]} > 0 )); then
        rm -f -- "${TMP_FILES[@]}"
    fi
}
trap cleanup EXIT

info() {
    echo -e "$1" >&2
}

die() {
    echo -e "${RED}$1${NC}" >&2
    exit 1
}

# --- События и история -----------------------------------------------------

escape_html() {
    # экранирует &, <, > для Telegram parse_mode=HTML
    local s="$1"
    s=${s//&/&amp;}
    s=${s//</&lt;}
    s=${s//>/&gt;}
    printf '%s' "$s"
}

log_event() {
    # log_event TYPE LOGIN PROJECT_ID TEXT [TITLE]
    local type="$1" login="$2" pid="$3" text="$4" title="${5:-}"
    local ts line
    ts="$(date '+%Y-%m-%dT%H:%M:%S%z')"
    if [[ -n "$title" ]]; then
        line="$ts | $type | $login | $pid | $text | $title"
    else
        line="$ts | $type | $login | $pid | $text"
    fi
    echo "$line"
    echo "$line" >> "$HISTORY_FILE"
}

send_telegram() {
    # send_telegram <text> — отправляет сообщение в Telegram (HTML). Ошибки не фатальны.
    [[ -n "$TG_BOT_TOKEN" ]] || return 0
    if [[ -z "$TG_CHAT_ID" ]]; then
        info "  ${YELLOW}⚠️ TG_BOT_TOKEN задан, но нет TG_CHAT_ID — уведомление не отправлено${NC}"
        return 1
    fi
    local msg="$1"
    # лимит Telegram — 4096 символов; слишком длинное сообщение обрежем
    if (( ${#msg} > 3900 )); then
        msg="${msg:0:3900}
…(сообщение обрезано, подробности в peers_history.log)"
    fi
    # HTML parse_mode: реальные переводы строк работают, <br> — НЕ поддерживается.
    # Экранирование <=, <=> сделано на стороне вызывающего (escape_html).
    local resp
    if ! resp=$(curl -sS --max-time 20 -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d chat_id="$TG_CHAT_ID" \
        -d parse_mode=HTML \
        --data-urlencode "text=$msg" 2>&1); then
        info "  ${RED}⚠️ Telegram: сетевая ошибка: $resp${NC}"
        return 1
    fi
    if [[ "$(echo "$resp" | jq -r '.ok // false' 2>/dev/null)" != "true" ]]; then
        info "  ${RED}⚠️ Telegram API: ${resp:0:200}${NC}"
        return 1
    fi
    return 0
}

# --- Креденциалы и токен ---------------------------------------------------

load_env() {
    local env_file
    for env_file in "$SCRIPT_DIR/.env" "$HOME/.env"; do
        if [[ -f "$env_file" ]]; then
            set -a
            # shellcheck disable=SC1090
            source "$env_file"
            set +a
            return 0
        fi
    done
    if [[ -z "${S21_USERNAME:-}" || -z "${S21_PASSWORD:-}" ]]; then
        die "Не найдено ни одно из: $SCRIPT_DIR/.env, $HOME/.env; и переменные S21_USERNAME/S21_PASSWORD не заданы"
    fi
}

get_jwt_exp() {
    jq -r '[.access_token | split(".")[1] | @base64d | fromjson | .exp // 0] | .[0]' 2>/dev/null || echo 0
}

get_token() {
    [[ -n "${S21_USERNAME:-}" && -n "${S21_PASSWORD:-}" ]] || die "Нужны S21_USERNAME и S21_PASSWORD"
    local resp
    resp=$(curl -sS --max-time "$CURL_TIMEOUT" -X POST "$AUTH_URL" \
        -d "grant_type=password" \
        -d "client_id=$CLIENT_ID" \
        -d "username=$S21_USERNAME" \
        -d "password=$S21_PASSWORD") \
        || die "Ошибка запроса токена (auth)"
    local token exp
    token=$(echo "$resp" | jq -r '.access_token // empty')
    [[ -n "$token" ]] || { echo "$resp" >&2; die "Не удалось получить access_token"; }
    exp=$(echo "$resp" | get_jwt_exp)
    mkdir -p "$TOKEN_CACHE_DIR"
    jq -n --arg t "$token" --argjson e "$exp" '{token: $t, exp: ($e | tonumber)}' > "$TOKEN_CACHE_FILE.tmp.$$"
    mv "$TOKEN_CACHE_FILE.tmp.$$" "$TOKEN_CACHE_FILE"
    echo "$token"
}

get_token_cached() {
    if [[ -f "$TOKEN_CACHE_FILE" ]]; then
        local token exp now
        token=$(jq -r '.token // empty' "$TOKEN_CACHE_FILE" 2>/dev/null || echo "")
        exp=$(jq -r '.exp // 0' "$TOKEN_CACHE_FILE" 2>/dev/null || echo 0)
        now=$(date +%s)
        if [[ -n "$token" && "${exp:-0}" -gt $((now + 60)) ]]; then
            echo "$token"
            return 0
        fi
        info "  Токен истёк или просрочен — получаем новый..."
    else
        info "  Кэша токена нет — получаем новый..."
    fi
    get_token
}

# --- API -------------------------------------------------------------------

api_get() {
    # api_get <token> <path> -> JSON в stdout; сетевая ошибка или HTTP не-2xx -> return 1
    local token="$1" path="$2" attempt=0 http_code body
    while (( attempt <= API_RETRIES )); do
        if ! body=$(curl -sS --max-time "$CURL_TIMEOUT" -w '\n%{http_code}' \
            -H "Authorization: Bearer $token" \
            "$BASE_URL$path"); then
            attempt=$((attempt + 1))
            (( attempt <= API_RETRIES )) && sleep 2
            continue
        fi
        http_code="${body##*$'\n'}"
        body="${body%$'\n'*}"
        if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
            echo "$body"
            return 0
        fi
        attempt=$((attempt + 1))
        (( attempt <= API_RETRIES )) && sleep 2
    done
    echo "api_get: HTTP $http_code для $path (последний ответ: ${body:0:300})" >&2
    return 1
}

fetch_peer_projects() {
    # fetch_peer_projects <login> <token> <out_file>
    # Полная пагинация списка проектов пира; каждая строка в out_file:
    # login \t project_id \t status \t title \t last_seen
    local login="$1" token="$2" out="$3"
    local offset=0 page n
    local now
    now="$(date '+%Y-%m-%dT%H:%M:%S%z')"
    while :; do
        page=$(api_get "$token" "/participants/$login/projects?limit=$PAGE_SIZE&offset=$offset") \
            || die "Не удалось получить проекты для $login (offset $offset) — цикл прерван, state не обновлён"
        n=$(echo "$page" | jq '.projects | length')
        [[ "$n" =~ ^[0-9]+$ ]] || die "Неожиданный ответ API для $login: $page"
        echo "$page" | jq -r --arg l "$login" --arg now "$now" \
            '.projects[] | [$l, (.id|tostring), (.status // "UNKNOWN"), (.title // ""), $now] | @tsv' >> "$out"
        (( n < PAGE_SIZE )) && break
        offset=$((offset + n))
        sleep 0.3
    done
    return 0
}

# --- Основной цикл ---------------------------------------------------------

read_peers() {
    # Логины по одному на строку, пустые строки и #-комментарии пропускаются
    [[ -f "$PEERS_FILE" ]] || die "Файл пиров не найден: $PEERS_FILE"
    local l
    while IFS= read -r l || [[ -n "$l" ]]; do
        l="$(printf '%s' "$l" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
        [[ -z "$l" || "$l" == \#* ]] && continue
        echo "$l"
    done < "$PEERS_FILE"
}

run_cycle() {
    local token
    token=$(get_token_cached)

    local tmp_new peer total_lines
    new_tmp tmp_new
    local peers=()
    while IFS= read -r peer; do
        peers+=("$peer")
    done < <(read_peers)
    (( ${#peers[@]} > 0 )) || die "В $PEERS_FILE нет ни одного логина"

    info "🔄 Опрос пиров: ${peers[*]}..."
    for peer in "${peers[@]}"; do
        fetch_peer_projects "$peer" "$token" "$tmp_new"
    done
    total_lines=$(wc -l < "$tmp_new")
    info "  ✓ Снимок: $total_lines проектов по ${#peers[@]} пирам"

    if [[ ! -f "$STATE_FILE" ]]; then
        mv "$tmp_new" "$STATE_FILE"
        local ts
        ts="$(date '+%Y-%m-%dT%H:%M:%S%z')"
        echo "$ts | BASELINE | - | - | создан первый снимок: $total_lines проектов" >> "$HISTORY_FILE"
        info "${GREEN}Базовый снимок создан: $STATE_FILE${NC}"
        return 0
    fi

    # Пиров, которых не было в старом снимке / которых больше нет (для bootstrapping)
    local tmp_np tmp_pr
    new_tmp tmp_np
    new_tmp tmp_pr
    comm -13 <(cut -f1 "$STATE_FILE" | sort -u) <(cut -f1 "$tmp_new" | sort -u) > "$tmp_np"
    comm -13 <(cut -f1 "$tmp_new" | sort -u) <(cut -f1 "$STATE_FILE" | sort -u) > "$tmp_pr"

    # Сравнение: STATE_FILE (старый) vs tmp_new (новый), ключ = login|project_id.
    # Для пиров, которых не было в старом снимке (tmp_np), события NEW не выдаются
    # (заменятся одним PEER_ADDED); для удалённых пиров — аналогично с GONE.
    local events
    events=$(awk -F'\t' -v npfile="$tmp_np" '
        BEGIN {
            while ((getline nl < npfile) > 0) isnew[nl] = 1
            close(npfile)
        }
        NR==FNR {
            old_status[$1 "\037" $2] = $3
            old_title[$1 "\037" $2]  = $4
            next
        }
        {
            key = $1 "\037" $2
            new_status[key] = $3
            new_title[key]  = $4
            newlogins[$1]   = 1
            seen[key] = 1
        }
        END {
            for (k in new_status) {
                split(k, a, "\037")
                if (!(k in old_status)) {
                    if (a[1] in isnew) continue
                    printf "NEW\t%s\t%s\tstatus=%s\t%s\n", a[1], a[2], new_status[k], new_title[k]
                } else if (old_status[k] != new_status[k])
                    printf "CHANGED\t%s\t%s\t%s -> %s\t%s\n", a[1], a[2], old_status[k], new_status[k], new_title[k]
            }
            for (k in old_status) {
                if (!(k in seen)) {
                    split(k, a, "\037")
                    if (!(a[1] in newlogins)) continue
                    printf "GONE\t%s\t%s\twas=%s\t%s\n", a[1], a[2], old_status[k], old_title[k]
                }
            }
        }
    ' "$STATE_FILE" "$tmp_new" | LC_ALL=C sort)

    local count=0 type login pid text title
    local tg_body=""
    while IFS=$'\t' read -r type login pid text title; do
        [[ -z "${type:-}" ]] && continue
        case "$type" in
            CHANGED) info "  ${YELLOW}⇄ $login: $pid ($text)${NC} — $title" ;;
            NEW)     info "  ${GREEN}+ $login: $pid ($text)${NC} — $title" ;;
            GONE)    info "  ${RED}- $login: $pid ($text)${NC} — $title" ;;
        esac
        log_event "$type" "$login" "$pid" "$text" "$title"
        local el et
        el=$(escape_html "$login"); et=$(escape_html "$title")
        case "$type" in
            CHANGED) tg_body+="⇄ <b>$el</b> · $et ($pid): ${text//->/→}"$'\n' ;;
            NEW)     tg_body+="+ <b>$el</b> · $et ($pid): $text"$'\n' ;;
            GONE)    tg_body+="- <b>$el</b> · $et ($pid): $text"$'\n' ;;
        esac
        count=$((count + 1))
    done <<< "$events"

    # Пиров, которых нет в старом снимке — один PEER_ADDED на пира (без 600+ NEW)
    local p pcnt
    while IFS= read -r p; do
        [[ -z "$p" ]] && continue
        pcnt=$(awk -F'\t' -v p="$p" '$1 == p' "$tmp_new" | wc -l)
        log_event "PEER_ADDED" "$p" "-" "новый пир: $pcnt проектов (baseline)"
        el=$(escape_html "$p")
        tg_body+="+ <b>$el</b>: добавлен в peers.txt ($pcnt проектов)"$'\n'
        count=$((count + 1))
    done < "$tmp_np"

    # Пиров, которых больше нет в новом снимке — один PEER_REMOVED на пира
    while IFS= read -r p; do
        [[ -z "$p" ]] && continue
        log_event "PEER_REMOVED" "$p" "-" "удалён из peers.txt"
        el=$(escape_html "$p")
        tg_body+="- <b>$el</b>: удалён из peers.txt"$'\n'
        count=$((count + 1))
    done < "$tmp_pr"

    mv "$tmp_new" "$STATE_FILE"
    if (( count == 0 )); then
        info "  Изменений нет"
    else
        info "  Всего событий: $count (см. $HISTORY_FILE)"
        local tg_ts
        tg_ts="$(date '+%H:%M:%S %Z')"
        send_telegram "📣 peer-poller ($tg_ts): $count изменений

$tg_body"
    fi
    return 0
}

show_snapshot() {
    [[ -f "$STATE_FILE" ]] || die "Снимка нет: $STATE_FILE (сначала запустите опрос)"
    info "Активные проекты (IN_PROGRESS / IN_REVIEWS / ACCEPTED):"
    awk -F'\t' '$3 ~ /^(IN_PROGRESS|IN_REVIEWS|ACCEPTED)$/ {
        printf "%-12s %-8s %-12s %s\n", $1, $2, $3, $4
    }' "$STATE_FILE" | LC_ALL=C sort -k1,1 -k3,3 -k2,2
    local n
    n=$(awk -F'\t' '$3 ~ /^(IN_PROGRESS|IN_REVIEWS|ACCEPTED)$/' "$STATE_FILE" | wc -l)
    info "Итого: $n"
}

usage() {
    sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
}

# --- main ------------------------------------------------------------------

MODE="once"
case "${1:-}" in
    ""|--once)  MODE="once" ;;
    --loop)     MODE="loop" ;;
    --show)     show_snapshot; exit 0 ;;
    --reset)
        [[ -f "$STATE_FILE" ]] && rm -f "$STATE_FILE"
        info "Базовый снимок сброшен (при следующем опросе будет создан заново)"
        exit 0
        ;;
    -h|--help)  usage; exit 0 ;;
    --test-tg)
        [[ -d "$STATE_DIR" ]] || mkdir -p "$STATE_DIR"
        load_env
        if [[ -z "${TG_BOT_TOKEN:-}" ]]; then
            die "TG_BOT_TOKEN не задан (в .env или окружении)"
        fi
        if send_telegram "✅ peer-poller: тестовое уведомление
время: $(date '+%Y-%m-%d %H:%M:%S %Z')
если видишь две строки — HTML-режим и переводы строк работают"; then
            info "Тестовое сообщение отправлено (OK)"
        else
            die "Не удалось отправить сообщение в Telegram"
        fi
        exit 0
        ;;
    *)          die "Неизвестный аргумент: $1 (см. --help)" ;;
esac

[[ -d "$STATE_DIR" ]] || mkdir -p "$STATE_DIR"
touch "$HISTORY_FILE"

load_env

if [[ "$MODE" == "once" ]]; then
    run_cycle
else
    info "🔁 Демон-режим: интервал ${POLL_INTERVAL}с (+0..60с джиттер). Ctrl+C для остановки."
    while :; do
        if ! run_cycle; then
            info "${RED}⚠️ Цикл завершился с ошибкой, повтор через ${POLL_INTERVAL}с${NC}"
        fi
        sleep "$((POLL_INTERVAL + RANDOM % 60))"
    done
fi


