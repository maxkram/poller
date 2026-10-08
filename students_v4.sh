#!/bin/bash
#
# ---------------------------------------------------------------------------
# Примеры запуска:
# ./students_v4.sh -p 62954 --format csv | awk -F',' 'NR>1 {print $1}'
# ./students_v4.sh -p 26481 -u
# ./students_v4.sh -p 26481 --city Ufa --status-summary
# ./students_v4.sh -p 26481 --status-summary --all-campuses
# ./students_v4.sh -p 26481 --city Ufa --top 10
# ./students_v4.sh --global-top 10
# ./students_v4.sh --global-top 10 --include-excluded-campuses
# ./students_v4.sh --global-top 20 --city Ufa --format csv
# ./students_v4.sh -p 26481 --city Ufa --accepted-trend week --format csv
# ./students_v4.sh -p 26481 --compare-cities Ufa,SPB,Kazan --format json
# ./students_v4.sh -p 69114 -s ACCEPTED -f csv -q | tail -n +2 | cut -d, -f1
#
# for pid in 62958 62959 62960; do
#   ./students_v4.sh -p "$pid" -s IN_REVIEWS,IN_PROGRESS,ACCEPTED,REGISTERED -f csv -q | tail -n +2 | cut -d',' -f1
# done | sort -u
# ---------------------------------------------------------------------------

AUTH_URL="https://auth.21-school.ru/auth/realms/EduPowerKeycloak/protocol/openid-connect/token"
BASE_URL="https://platform.21-school.ru/services/21-school/api/v1"
CLIENT_ID="s21-open-api"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

TOKEN_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/s21"
TOKEN_CACHE_FILE="$TOKEN_CACHE_DIR/token.json"

# Список кампусов (id | short_name | full_name | city), обновлено: 2026-04-11
# 406287c1-89e2-45d8-a1a4-0839c48cd5c7 | 21 VGIK                          | Школа 21, ВГИК                   | ВГИК
# 7551a717-01a3-455f-8857-e5e79896f4f5 | 21 Novy Urengoy                  | Школа 21, Новый Уренгой          | Новый Уренгой
# c707e947-a097-459f-8c82-5ca548e46abe | Canary 21                        | Canary 21                        | Canary 21
# 07a3fa7e-2640-4330-a902-0752178df949 | 21 Yakutsk                       | Школа 21, Якутск                 | Якутск
# e786cbfb-ed04-4e0e-8a01-6b0fa2256634 | 21 Ufa                           | Школа 21, Уфа                    | Уфа
# 911fbc82-b821-4699-82ee-15184a5e6cef | 21 Surgut                        | Школа 21, Сургут                 | Сургут
# 04989f19-21a3-41c0-af4e-89db4d8d4c6b | 21 Sakhalin                      | Школа 21, Сахалин                | Сахалин
# 667a42af-5469-4a33-9858-677d9d20956a | 21 Samarkand                     | Школа 21, Самарканд              | Самарканд
# 5a23bec9-f989-485d-935b-3f0dc61c4812 | 21 Nizhny Novgorod               | Школа 21, Нижний Новгород        | Нижний Новгород
# c3809b97-5910-453c-b486-8fcc58a8cc32 | 21 Magas                         | Школа 21, Магас                  | Магас
# ebc4fada-4f32-4948-9ec6-8a2e73a3077a | 21 Lipetsk                       | Школа 21, Липецк                 | Липецк
# a4a9fa63-63c0-4e81-a5ff-e1501d74362c | 21 Veliky Novgorod               | Школа 21, Великий Новгород       | Великий Новгород
# 981e10b5-7553-406a-940e-83d34342c113 | 21 Belgorod                      | Школа 21, Белгород               | Белгород
# c3b555f4-4504-4ce4-9457-9ca75c1a354d | 21 Anadyr                        | Школа 21, Анадырь                | Анадырь
# e561d833-400b-44f5-a6ac-951b0378a9f6 | School 21 online                 | School 21 online                 | School 21 online
# 8832e878-577e-4583-847a-d7e1db5d5507 | 21 Test                          | 21 Тестовый кампус               | 21 Тестовый кампус
# 4e77f0e8-7b08-4024-b7cc-c21542235995 | 21 Omsk                          | Школа 21, Омск                   | Омск
# 9bc1136e-b5c8-4dd1-94e8-f94e4029c9f8 | 21 Test QA                       | Кампус Ш21 (ТЕСТ)                | Кампус Ш21 (ТЕСТ)
# 6bfe3c56-0211-4fe1-9e59-51616caac4dd | 21 Moscow                        | Школа 21, Москва                 | Москва
# 7c293c9c-f28c-4b10-be29-560e4b000a34 | 21 Kazan                         | Школа 21, Казань                 | Казань
# 46e7d965-21e9-4936-bea9-f5ea0d1fddf2 | 21 Novosibirsk                   | Школа 21, Новосибирск            | Новосибирск
# b4b36a53-d253-4840-9000-49061d74bf50 | 21 Yaroslavl                     | Школа 21, Ярославль              | Ярославль
# c1f23996-0661-4fa8-ae27-6e0fb707d73e | 21 Chelyabinsk                   | Школа 21, Челябинск              | Челябинск
# bad03b39-ffd4-4217-9d24-65535fe1f293 | 21 Tashkent                      | Школа 21, Ташкент                | Ташкент
# bfe5399d-33e9-43b4-a97f-732c39a6ddc8 | 21 Magadan                       | Школа 21, Магадан                | Магадан
# 52acbcb1-f203-401e-a013-ecd0e74fb531 | 21 Sechenov                      | Школа 21 Sechenov, Москва        | Москва
# 29800e0c-12d3-4a46-b9ff-45866a6ff605 | 21 RUDN                          | Школа 21, РУДН                   | РУДН
# e33eae7d-dc6d-406f-8619-6834daa26eaa | Школа 21 Старт, Новый Уренгой    | Школа 21 Старт, Новый Уренгой    | Новый Уренгой
# 14b2cc80-bdce-4c71-b29e-3c1457d81130 | 21 Volgograd                     | Школа 21, Волгоград              | Волгоград
# d97c0118-2ec7-488e-ac76-289392aeafee | Школа 21 Старт, Челябинск        | Школа 21 Старт, Челябинск        | Челябинск
# 086a749b-f7aa-4eff-9ff9-40e8ae404041 | Школа 21 Старт, Уфа              | Школа 21 Старт, Уфа              | Уфа
# 1e9f4e01-4a88-4c16-bd6a-4645ce9079f1 | Школа 21 Старт, Тестовый кампус  | Школа 21 Старт, Тестовый кампус  | Тестовый кампус
# 6967bc67-955b-44a8-8d8d-be8b1584374d | 21 Stavropol                     | Школа 21, Ставрополь             | Ставрополь
# 11213bb0-c331-4980-8316-944a35f1c905 | 21 Ulan-Ude                      | Школа 21, Улан-Удэ               | Улан-Удэ
# e7e2ef82-0c24-48b6-9e22-2468323083eb | 21 Perm                          | Школа 21, Пермь                  | Пермь
# 11c46287-4a3e-462d-b6b2-bcfe71b5d9dd | 21 Izhevsk                       | Школа 21, Ижевск                 | Ижевск
# decb6a3a-efd7-4224-945a-c4e81d8ab90b | 21 Almazov                       | Школа 21, Алмазов                | Алмазов
# 6d4b8669-4107-47bd-96d0-380e7b5d1ad8 | Школа 21 Старт, Москва           | Школа 21 Старт, Москва           | Москва
# 2a2cc733-e994-468d-ba5f-f7a5592ac7f6 | 21 Dushanbe                      | Школа 21, Душанбе                | Душанбе

EXCLUDED_CAMPUS_IDS=(
    # "6bfe3c56-0211-4fe1-9e59-51616caac4dd" # 21 Moscow
    # "7c293c9c-f28c-4b10-be29-560e4b000a34" # 21 Kazan
    # "46e7d965-21e9-4936-bea9-f5ea0d1fddf2" # 21 Novosibirsk
    "667a42af-5469-4a33-9858-677d9d20956a" # 21 Samarkand
    "8832e878-577e-4583-847a-d7e1db5d5507" # 21 Test
    "9bc1136e-b5c8-4dd1-94e8-f94e4029c9f8" # 21 Test QA
    "bad03b39-ffd4-4217-9d24-65535fe1f293" # 21 Tashkent
    "2a2cc733-e994-468d-ba5f-f7a5592ac7f6" # 21 Dushanbe
    "29800e0c-12d3-4a46-b9ff-45866a6ff605" # 21 RUDN
    "52acbcb1-f203-401e-a013-ecd0e74fb531" # 21 Sechenov
    "c707e947-a097-459f-8c82-5ca548e46abe" # Canary 21
    "406287c1-89e2-45d8-a1a4-0839c48cd5c7" # 21 VGIK
    "d97c0118-2ec7-488e-ac76-289392aeafee" # Школа 21 Старт, Челябинск
    "6d4b8669-4107-47bd-96d0-380e7b5d1ad8" # Школа 21 Старт, Москва
    "e33eae7d-dc6d-406f-8619-6834daa26eaa" # Школа 21 Старт, Новый Уренгой
    "086a749b-f7aa-4eff-9ff9-40e8ae404041" # Школа 21 Старт, Уфа
    "1e9f4e01-4a88-4c16-bd6a-4645ce9079f1" # Школа 21 Старт, Тестовый кампус
    "decb6a3a-efd7-4224-945a-c4e81d8ab90b" # 21 Almazov
)

EXCLUDED_CAMPUS_NAMES=(
    "Canary 21"
    "School 21 online"
    "Школа 21 Старт, Москва"
    "Школа 21 Старт, Новый Уренгой"
    "Школа 21 Старт, Тестовый кампус"
    "Школа 21 Старт, Уфа"
    "Школа 21 Старт, Челябинск"
    "Dushanbe"
    "Almazov"
    "21 RUDN"
    "21 Sechenov"
    "21 Test QA"
    "21 Test"
    "Samarkand"
    "VGIK"
    "Moscow"
)

DEFAULT_STATUSES="REGISTERED,IN_PROGRESS,IN_REVIEWS,ACCEPTED,FAILED"
# DEFAULT_STATUSES="ACCEPTED"


declare -A PROJECT_NAMES=(
    [73244]="UX/UI3_UI Design"
    [71030]="CbS3_Networking_basics_Part 3"
    [26561]="DO3_LinuxMonitoring v1.0"
    [62393]="ML2_Supervised learning"
    [72880]="QA3_Test design and test analysis"
    [69542]="BSA2_Requirements"
    [26481]="C5_s21_decimal"
)

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; PURPLE='\033[0;35m'; CYAN='\033[0;36m'
NC='\033[0m'

QUIET="false"
INCLUDE_EXCLUDED_CAMPUSES="false"
NO_TOKEN_CACHE="false"

# Кэш login -> "campus_id|campus_name" на время запуска (гасит N+1 по статусам)
declare -A CAMPUS_CACHE=()

# --- Временные файлы: единая регистрация + trap cleanup ---
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
    if [[ "$QUIET" != "true" ]]; then
        echo -e "$1" >&2
    fi
}

die() {
    echo -e "${RED}$1${NC}" >&2
    exit 1
}

get_project_name() {
    local project_id="$1"
    if [[ -z "$project_id" ]]; then
        echo ""
        return
    fi
    echo "${PROJECT_NAMES[$project_id]:-}"
}

is_campus_excluded() {
    local campus_id="$1"

    if [[ "$INCLUDE_EXCLUDED_CAMPUSES" == "true" ]]; then
        return 1
    fi

    local excluded_id
    for excluded_id in "${EXCLUDED_CAMPUS_IDS[@]}"; do
        if [[ "$campus_id" == "$excluded_id" ]]; then
            return 0
        fi
    done
    return 1
}

is_campus_name_excluded() {
    local campus_name="$1"
    local excluded_name

    if [[ "$INCLUDE_EXCLUDED_CAMPUSES" == "true" ]]; then
        return 1
    fi

    case "$campus_name" in "Школа 21 Старт"*) return 0 ;; esac

    for excluded_name in "${EXCLUDED_CAMPUS_NAMES[@]}"; do
        if [[ "$campus_name" == "$excluded_name" ]]; then
            return 0
        fi
    done
    return 1
}

load_env() {
    if [[ -f "$ENV_FILE" ]]; then
        set -a
        # shellcheck disable=SC1090
        source "$ENV_FILE"
        set +a

        local perms
        perms=$(stat -c '%a' "$ENV_FILE" 2>/dev/null || echo "600")
        if [[ "$perms" != "600" && "$perms" != "400" && "$perms" != "700" ]]; then
            info "  ⚠️ Права на $ENV_FILE: $perms — выполните: chmod 600 $ENV_FILE"
        fi
    elif [[ -z "${S21_USERNAME:-}" || -z "${S21_PASSWORD:-}" ]]; then
        die "Файл $ENV_FILE не найден и переменные S21_USERNAME/S21_PASSWORD не заданы в окружении"
    fi

    if [[ -z "${S21_USERNAME:-}" || -z "${S21_PASSWORD:-}" ]]; then
        die "Нужны S21_USERNAME и S21_PASSWORD (в .env или в окружении)"
    fi
}

print_help() {
    cat <<EOF
Использование:
  ./students_v4.sh --project-id ID [опции]

Базовые опции:
  -p, --project-id ID       ID проекта
      --project-info        Информация о проекте по ID, без списка участников
  -s, --statuses LIST       Статусы через запятую (по умолчанию: $DEFAULT_STATUSES)
  -c, --city NAME           Город/кампус (например: Ufa)
      --all-campuses        Все кампусы (кроме исключенных) для --status-summary
      --include-excluded-campuses  Включить ранее исключенные кампусы
      --compare-cities L    Сравнить города (через запятую), пример: Ufa,SPB,Kazan
  -f, --format TYPE         Формат вывода: plain|json|csv (по умолчанию: plain)
  -q, --quiet               Тихий режим (меньше логов в stderr)
      --force-city          Не отбрасывать исключенные кампусы при разрешении --city
      --fresh-token         Не использовать кэш токена (принудительная авторизация)
  -h, --help                Показать справку

Режимы:
  -u, --ufa-accepted-count  Количество ACCEPTED по проекту в Ufa
    --status-summary        Сводка по статусам для города (--city) или по всем кампусам (--all-campuses)
    --top N                 Топ N студентов проекта в городе (--city) по метрикам
    --global-top N          Глобальный топ N по сумме очков pointsTotal (по всем кампусам или по --city)
    --accepted-trend G      Динамика ACCEPTED в городе (--city), G: day|week

Примеры:
  ./students_v4.sh -p 26481 -u
  ./students_v4.sh -p 26481 --city Ufa --status-summary
  ./students_v4.sh -p 26481 --status-summary --all-campuses
  ./students_v4.sh -p 26481 --city Ufa --top 10
  ./students_v4.sh --global-top 10
  ./students_v4.sh --global-top 10 --include-excluded-campuses
  ./students_v4.sh --global-top 20 --city Ufa --format csv
  ./students_v4.sh -p 26481 --city Ufa --accepted-trend week --format csv
  ./students_v4.sh -p 26481 --compare-cities Ufa,SPB,Kazan --format json

Кэш токена: $TOKEN_CACHE_FILE (сброс: --fresh-token)
EOF
}

get_token() {
    local username="$S21_USERNAME" password="$S21_PASSWORD"
    local attempts=5
    local attempt response token error_description

    for ((attempt=1; attempt<=attempts; attempt++)); do
        info "  ↳ Авторизация: попытка $attempt/$attempts..."

        if ! response=$(curl -sS --connect-timeout 10 --max-time 40 -X POST "$AUTH_URL" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            --data-urlencode "client_id=$CLIENT_ID" \
            --data-urlencode "username=$username" \
            --data-urlencode "password=$password" \
            --data-urlencode "grant_type=password"); then
            info "  ⚠️ Сеть недоступна или таймаут при получении токена"
            sleep "$attempt"
            continue
        fi

        token=$(echo "$response" | jq -r '.access_token // empty' 2>/dev/null)
        if [[ -n "$token" ]]; then
            info "  ✓ Токен успешно получен"
            echo "$token"
            return 0
        fi

        error_description=$(echo "$response" | jq -r '.error_description // .error // empty' 2>/dev/null)
        if [[ -n "$error_description" ]]; then
            info "  ⚠️ Ответ auth-сервиса: $error_description"
            # Не дёргаем auth 5 раз при неверных кредах — Keycloak ловит брутфорс
            if [[ "$error_description" == *"credentials"* || "$error_description" == *"invalid_grant"* ]]; then
                die "Неверный логин или пароль — повторы прекращены"
            fi
        else
            info "  ⚠️ Auth-сервис вернул неожиданный ответ"
        fi

        sleep "$attempt"
    done

    return 1
}

# exp из JWT (payload, base64url) — без внешних зависимостей кроме jq/base64
jwt_exp() {
    local seg b64 len
    seg=$(printf '%s' "$1" | cut -d'.' -f2)
    [[ -z "$seg" ]] && return 1
    b64=$(printf '%s' "$seg" | tr '_-' '/+')
    len=$((${#b64} % 4))
    case "$len" in
        2) b64+="==" ;;
        3) b64+="=" ;;
    esac
    printf '%s' "$b64" | base64 -d 2>/dev/null | jq -r '.exp // empty' 2>/dev/null
}

get_token_cached() {
    local token exp now

    if [[ "$NO_TOKEN_CACHE" == "false" && -f "$TOKEN_CACHE_FILE" ]]; then
        token=$(jq -r '.token // empty' "$TOKEN_CACHE_FILE" 2>/dev/null)
        exp=$(jq -r '.exp // empty' "$TOKEN_CACHE_FILE" 2>/dev/null)
        now=$(date +%s)
        if [[ -n "$token" && -n "$exp" ]] && (( exp - now > 60 )); then
            info "  ✓ Токен из кэша (действителен ещё $((exp - now)) с)"
            echo "$token"
            return 0
        fi
    fi

    token=$(get_token) || return 1

    if [[ "$NO_TOKEN_CACHE" == "false" ]]; then
        exp=$(jwt_exp "$token")
        now=$(date +%s)
        # если exp не удалось разобрать — консервативно кэшируем на 5 минут
        if [[ -z "$exp" ]] || (( exp <= now )); then
            exp=$((now + 300))
        fi
        mkdir -p "$TOKEN_CACHE_DIR" 2>/dev/null
        if [[ -d "$TOKEN_CACHE_DIR" ]]; then
            chmod 700 "$TOKEN_CACHE_DIR" 2>/dev/null
            printf '{"token":"%s","exp":%s}\n' "$token" "$exp" > "$TOKEN_CACHE_FILE"
            chmod 600 "$TOKEN_CACHE_FILE" 2>/dev/null
        fi
    fi

    echo "$token"
}

api_get() {
    local token="$1" path="$2" attempt http_code curl_rc body_file
    for ((attempt=1; attempt<=4; attempt++)); do
        body_file=$(mktemp) || return 1
        http_code=$(curl -sS --connect-timeout 10 --max-time 40 --retry 0 \
            -o "$body_file" -w '%{http_code}' -H 'Accept: application/json' \
            -H "Authorization: Bearer $token" "$BASE_URL$path")
        curl_rc=$?
        if (( curl_rc == 0 )) && [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
            cat -- "$body_file"
            rm -f -- "$body_file"
            return 0
        fi
        rm -f -- "$body_file"
        case "$http_code" in
            401|403|404|400)
                printf 'HTTP %s: запрос отклонён: %s\n' "$http_code" "$path" >&2
                return 1 ;;
            429|5??) ;;
            *) if (( curl_rc == 0 )); then
                   printf 'HTTP %s: запрос отклонён: %s\n' "$http_code" "$path" >&2
                   return 1
               fi ;;
        esac
        (( attempt < 4 )) && sleep $((attempt * 2))
    done
    printf 'Ошибка запроса: %s (HTTP %s, curl %s)\n' "$path" "$http_code" "$curl_rc" >&2
    return 1
}
get_campuses_json() {
    local token="$1"
    local attempts=8
    local i campuses_json

    for ((i=1; i<=attempts; i++)); do
        campuses_json=$(api_get "$token" "/campuses")
        if echo "$campuses_json" | jq -e '.campuses and (.campuses | type == "array")' >/dev/null 2>&1; then
            echo "$campuses_json"
            return 0
        fi

        # API иногда отдаёт plain text (rate limit) — ждём и пробуем снова
        if echo "$campuses_json" | grep -qi "Too many requests"; then
            sleep $((i * 2))
        else
            sleep 1
        fi
    done

    return 1
}

# Возвращает "campus_id|short_name" первого подходящего кампуса.
get_campus_id_by_city() {
    local token="$1" city="$2" include_excluded="$3"
    local campuses_json resolved

    if [[ -z "$include_excluded" ]]; then
        include_excluded="false"
    fi

    if ! campuses_json=$(get_campuses_json "$token"); then
        return 2
    fi
    resolved=$(echo "$campuses_json" | jq -r --arg city "${city,,}" '
        .campuses[]?
        | select((.shortName | ascii_downcase | contains($city)) or (.fullName | ascii_downcase | contains($city)))
        | "\(.id)|\(.shortName)"
    ' | while IFS='|' read -r cid cname; do
        if [[ "$include_excluded" == "true" ]] || { ! is_campus_excluded "$cid" && ! is_campus_name_excluded "$cname"; }; then
            echo "$cid|$cname"
            break
        fi
    done)

    echo "$resolved"
}

get_active_campuses() {
    local token="$1"
    local campuses_json

    if ! campuses_json=$(get_campuses_json "$token"); then
        return 2
    fi
    echo "$campuses_json" | jq -r '.campuses[]? | "\(.id)|\(.shortName)"' | while IFS='|' read -r cid short_name; do
        if ! is_campus_excluded "$cid" && ! is_campus_name_excluded "$short_name"; then
            echo "$cid|$short_name"
        fi
    done
}

get_all_campuses() {
    local token="$1"
    local campuses_json

    if ! campuses_json=$(get_campuses_json "$token"); then
        return 2
    fi
    echo "$campuses_json" | jq -r '.campuses[]? | "\(.id)|\(.shortName)"'
}

# Ни одна страница не пропускается: ошибочная выборка не публикуется.
fetch_participants() {
    local token="$1" prefix="$2" limit=1000 offset=0
    local response attempt count page previous=""
    local -a results=()
    while true; do
        for ((attempt=1; attempt<=4; attempt++)); do
            if response=$(api_get "$token" "${prefix}limit=$limit&offset=$offset") &&
                printf '%s' "$response" | jq -e '.participants | type == "array"' >/dev/null 2>&1; then
                break
            fi
            (( attempt < 4 )) && sleep "$attempt"
        done
        if (( attempt > 4 )); then
            info "Ошибка: страница участников offset=$offset недоступна"
            return 1
        fi
        count=$(printf '%s' "$response" | jq -r '.participants | length') || return 1
        (( count == 0 )) && break
        page=$(printf '%s' "$response" | jq -er '.participants | if all(.[]; type == "string" and length > 0) then .[] else error("invalid login") end') || return 1
        if (( offset > 0 )) && [[ "$page" == "$previous" ]]; then
            info "Ошибка: API повторяет страницу offset=$offset"
            return 1
        fi
        previous="$page"
        while IFS= read -r login; do results+=("$login"); done <<< "$page"
        (( count < limit )) && break
        offset=$((offset + limit))
    done
    if (( ${#results[@]} )); then printf '%s\n' "${results[@]}"; fi
}

get_participants_by_campus() {
    fetch_participants "$1" "/campuses/$2/participants?"
}

get_participants_by_status() {
    local prefix="/projects/$2/participants?status=$3&"
    [[ -n "$4" ]] && prefix+="campusId=$4&"
    fetch_participants "$1" "$prefix"
}

get_unique_participants_for_statuses() {
    local token="$1" project_id="$2" statuses_csv="$3" campus_id="$4"
    local status login campus_info campus_id_student campus_name_student student_status
    local -a participants_raw=()
    local -a statuses_arr=()

    IFS=',' read -r -a statuses_arr <<< "$statuses_csv"
    for status in "${statuses_arr[@]}"; do
        info "  🔍 Статус $status..."
        local status_file
        new_tmp status_file
        get_participants_by_status "$token" "$project_id" "$status" "$campus_id" > "$status_file" || return 1
        while IFS= read -r login; do
            [[ -z "$login" ]] && continue

            if [[ -n "$campus_id" ]]; then
                student_status=$(get_student_status "$token" "$login") || return 1
                if [[ "$student_status" == "FROZEN" || "$student_status" == "EXPELLED" || "$student_status" == "TEMPORARY_BLOCKING" ]]; then
                    info "  ⚠️ Участник $login имеет статус $student_status — пропускаем"
                    continue
                fi
                participants_raw+=("$login")
                continue
            fi

            if [[ -n "${CAMPUS_CACHE[$login]+x}" ]]; then
                campus_info="${CAMPUS_CACHE[$login]}"
            else
                campus_info=$(get_student_campus "$token" "$login") || return 1
                CAMPUS_CACHE["$login"]="$campus_info"
            fi
            campus_id_student="${campus_info%%|*}"
            campus_name_student="${campus_info#*|}"
            student_status="${campus_info##*|}"

            if [[ "$student_status" == "FROZEN" || "$student_status" == "EXPELLED" || "$student_status" == "TEMPORARY_BLOCKING" ]]; then
                info "  ⚠️ Участник $login имеет статус $student_status — пропускаем"
                continue
            fi

            if ! is_campus_excluded "$campus_id_student" && ! is_campus_name_excluded "$campus_name_student"; then
                participants_raw+=("$login")
            fi
        done < "$status_file"
    done

    if (( ${#participants_raw[@]} == 0 )); then
        return 0
    fi
    printf "%s\n" "${participants_raw[@]}" | sed '/^$/d' | sort -u
}

get_student_campus() {
    local token="$1" login="$2"
    local response json_response campus_id campus_name status
    local attempts=3
    local attempt=1

    while (( attempt <= attempts )); do
        response=$(api_get "$token" "/participants/$login")
        json_response=$(echo "$response" | sed 's/^[^{]*//')

        if echo "$json_response" | jq -e 'type == "object" and (.status | type == "string") and (.campus.id | type == "string")' >/dev/null 2>&1; then
            campus_id=$(echo "$json_response" | jq -r '.campus.id // "unknown"')
            campus_name=$(echo "$json_response" | jq -r '.campus.shortName // "Неизвестно"')
            status=$(echo "$json_response" | jq -r '.status // "UNKNOWN"')

            # FROZEN, EXPELLED, TEMPORARY_BLOCKING — неактивные статусы
            if [[ "$status" == "FROZEN" || "$status" == "EXPELLED" || "$status" == "TEMPORARY_BLOCKING" ]]; then
                info "  ⚠️ Участник $login имеет статус $status — пропускаем"
                echo "inactive|$status|$status"
                return 0
            fi

            echo "$campus_id|$campus_name|$status"
            return 0
        fi

        info "  ⚠️ API вернул не-JSON для участника $login (попытка $attempt): ${response:0:200}"
        sleep "$attempt"
        attempt=$((attempt + 1))
    done

    return 1
}

get_student_status() {
    local response
    response=$(api_get "$1" "/participants/$2") || return 1
    printf '%s' "$response" | jq -er '.status | select(type == "string")'
}

get_participant_points_total() {
    local response
    response=$(api_get "$1" "/participants/$2") || return 1
    printf '%s' "$response" | jq -er '.expValue | select(type == "number")'
}

get_participant_avg_skill() {
    local response
    response=$(api_get "$1" "/participants/$2/skills") || return 1
    printf '%s' "$response" | jq -er '
        if (.skills | type) != "array" then error("invalid skills")
        elif (.skills | length) == 0 then 0
        elif all(.skills[]; (.points | type) == "number") then ([.skills[].points] | add) / (.skills | length)
        else error("invalid skill points") end
    '
}

get_project_completion_datetime() {
    local token="$1" login="$2" project_id="$3"
    local response json_response

    response=$(api_get "$token" "/participants/$login/projects/$project_id")
    json_response=$(echo "$response" | sed 's/^[^{]*//')
    if ! echo "$json_response" | jq . >/dev/null 2>&1; then
        info "  ⚠️ API вернул не-JSON для project $project_id участника $login: ${response:0:200}"
        echo ""
        return
    fi
    echo "$json_response" | jq -r '.completionDateTime // empty'
}

emit_count_result() {
    local label="$1" count="$2" format="$3"

    case "$format" in
        plain)
            printf '%b📊 %s: %d%b\n' "$GREEN" "$label" "$count" "$NC"
            ;;
        json)
            jq -n --arg label "$label" --argjson count "$count" '{label: $label, count: $count}'
            ;;
        csv)
            printf "label,count\n\"%s\",%d\n" "$label" "$count"
            ;;
        *)
            die "Неподдерживаемый формат: $format"
            ;;
    esac
}

emit_status_summary() {
    local project_id="$1" city="$2" format="$3" summary_file="$4"
    local project_name="$5"
    local total
    total=$(awk -F'|' '{sum+=$2} END{print sum+0}' "$summary_file")

    case "$format" in
        plain)
            if [[ -n "$project_name" ]]; then
                echo "Проект: $project_id ($project_name) | Город: $city"
            else
                echo "Проект: $project_id | Город: $city"
            fi
            printf "%-14s %10s\n" "Статус" "Количество"
            printf "%-14s %10s\n" "--------------" "----------"
            while IFS='|' read -r status cnt; do
                printf "%-14s %10d\n" "$status" "$cnt"
            done < "$summary_file"
            printf "%-14s %10s\n" "--------------" "----------"
            printf "%-14s %10d\n" "TOTAL" "$total"
            ;;
        json)
            jq -Rn --arg projectId "$project_id" --arg projectName "$project_name" --arg city "$city" '
                (input | split("|") | {status: .[0], count: (.[1] | tonumber)}) as $first
                | [ $first, (inputs | split("|") | {status: .[0], count: (.[1] | tonumber)}) ]
                | {projectId: $projectId, projectName: $projectName, city: $city, statuses: ., total: ([.[].count] | add)}
            ' < "$summary_file"
            ;;
        csv)
            printf "project_id,project_name,city,status,count\n"
            while IFS='|' read -r status cnt; do
                printf "%s,%s,%s,%s,%s\n" "$project_id" "$project_name" "$city" "$status" "$cnt"
            done < "$summary_file"
            printf "%s,%s,%s,TOTAL,%s\n" "$project_id" "$project_name" "$city" "$total"
            ;;
        *)
            die "Неподдерживаемый формат: $format"
            ;;
    esac
}

emit_all_campuses_status_summary() {
    local project_id="$1" format="$2" summary_file="$3" project_name="$4"
    local grand_total
    local campus_width

    grand_total=$(awk -F'|' '{sum+=$3} END{print sum+0}' "$summary_file")
    campus_width=$(awk -F'|' 'BEGIN{max=6} {if (length($1) > max) max=length($1)} END{print max+2}' "$summary_file")

    case "$format" in
        plain)
            if [[ -n "$project_name" ]]; then
                echo "Проект: $project_id ($project_name) | Все кампусы (кроме исключенных)"
            else
                echo "Проект: $project_id | Все кампусы (кроме исключенных)"
            fi
            printf "%-*s %10s %12s %11s %10s %8s %8s\n" "$campus_width" "Кампус" "REGISTERED" "IN_PROGRESS" "IN_REVIEWS" "ACCEPTED" "FAILED" "TOTAL"
            printf "%-*s %10s %12s %11s %10s %8s %8s\n" "$campus_width" "$(printf '%*s' "$campus_width" '' | tr ' ' '-')" "----------" "------------" "-----------" "----------" "--------" "--------"

            while IFS= read -r campus_name; do
                local reg in_prog in_rev acc fail row_total
                reg=$(awk -F'|' -v c="$campus_name" '$1==c && $2=="REGISTERED" {print $3}' "$summary_file")
                in_prog=$(awk -F'|' -v c="$campus_name" '$1==c && $2=="IN_PROGRESS" {print $3}' "$summary_file")
                in_rev=$(awk -F'|' -v c="$campus_name" '$1==c && $2=="IN_REVIEWS" {print $3}' "$summary_file")
                acc=$(awk -F'|' -v c="$campus_name" '$1==c && $2=="ACCEPTED" {print $3}' "$summary_file")
                fail=$(awk -F'|' -v c="$campus_name" '$1==c && $2=="FAILED" {print $3}' "$summary_file")

                reg=${reg:-0}
                in_prog=${in_prog:-0}
                in_rev=${in_rev:-0}
                acc=${acc:-0}
                fail=${fail:-0}
                row_total=$((reg + in_prog + in_rev + acc + fail))

                printf "%-*s %10d %12d %11d %10d %8d %8d\n" "$campus_width" "$campus_name" "$reg" "$in_prog" "$in_rev" "$acc" "$fail" "$row_total"
            done < <(cut -d'|' -f1 "$summary_file" | sort -u)

            printf "%-*s %10s %12s %11s %10s %8s %8s\n" "$campus_width" "$(printf '%*s' "$campus_width" '' | tr ' ' '-')" "----------" "------------" "-----------" "----------" "--------" "--------"
            printf "%-*s %10s %12s %11s %10s %8s %8d\n" "$campus_width" "TOTAL" "" "" "" "" "" "$grand_total"
            ;;
        json)
            jq -Rn --arg projectId "$project_id" --arg projectName "$project_name" '
                [inputs | split("|") | {campus: .[0], status: .[1], count: (.[2] | tonumber)}] as $rows
                | ($rows
                    | group_by(.campus)
                    | map({
                        campus: .[0].campus,
                        statuses: (map({key: .status, value: .count}) | from_entries),
                        total: (map(.count) | add)
                      })
                  ) as $campuses
                | {projectId: $projectId, projectName: $projectName, scope: "all_campuses", campuses: $campuses, total: ($campuses | map(.total) | add // 0)}
            ' < "$summary_file"
            ;;
        csv)
            printf "project_id,project_name,campus,status,count\n"
            while IFS='|' read -r campus_name status cnt; do
                printf "%s,%s,%s,%s,%s\n" "$project_id" "$project_name" "$campus_name" "$status" "$cnt"
            done < "$summary_file"

            while IFS= read -r campus_name; do
                local row_total
                row_total=$(awk -F'|' -v c="$campus_name" '$1==c {sum+=$3} END{print sum+0}' "$summary_file")
                printf "%s,%s,%s,TOTAL,%s\n" "$project_id" "$project_name" "$campus_name" "$row_total"
            done < <(cut -d'|' -f1 "$summary_file" | sort -u)

            printf "%s,%s,ALL,TOTAL,%s\n" "$project_id" "$project_name" "$grand_total"
            ;;
        *)
            die "Неподдерживаемый формат: $format"
            ;;
    esac
}

emit_compare_cities() {
    local project_id="$1" format="$2" compare_file="$3" project_name="$4"
    local city_width

    city_width=$(awk -F'|' 'BEGIN{max=5} {if (length($1) > max) max=length($1)} END{print max+2}' "$compare_file")

    case "$format" in
        plain)
            if [[ -n "$project_name" ]]; then
                echo "Сравнение городов по проекту $project_id ($project_name)"
            else
                echo "Сравнение городов по проекту $project_id"
            fi
            printf "%-*s %10s %10s %12s\n" "$city_width" "Город" "Всего" "Accepted" "SuccessRate%"
            printf "%-*s %10s %10s %12s\n" "$city_width" "$(printf '%*s' "$city_width" '' | tr ' ' '-')" "----------" "----------" "------------"
            while IFS='|' read -r city total accepted rate; do
                printf "%-*s %10d %10d %12s\n" "$city_width" "$city" "$total" "$accepted" "$rate"
            done < "$compare_file"
            ;;
        json)
            jq -Rn --arg projectId "$project_id" --arg projectName "$project_name" '
                (input | split("|") | {city: .[0], total: (.[1]|tonumber), accepted: (.[2]|tonumber), successRate: (.[3]|tonumber)}) as $first
                | [ $first, (inputs | split("|") | {city: .[0], total: (.[1]|tonumber), accepted: (.[2]|tonumber), successRate: (.[3]|tonumber)}) ]
                | {projectId: $projectId, projectName: $projectName, cities: .}
            ' < "$compare_file"
            ;;
        csv)
            printf "project_id,project_name,city,total,accepted,success_rate_percent\n"
            while IFS='|' read -r city total accepted rate; do
                printf "%s,%s,%s,%s,%s,%s\n" "$project_id" "$project_name" "$city" "$total" "$accepted" "$rate"
            done < "$compare_file"
            ;;
        *)
            die "Неподдерживаемый формат: $format"
            ;;
    esac
}

main() {
    local project_id=""
    local statuses_input="$DEFAULT_STATUSES"
    local city=""
    local all_campuses_mode="false"
    local include_excluded_campuses="false"
    local compare_cities=""
    local format="plain"

    local ufa_accepted_count_mode="false"
    local status_summary_mode="false"
    local top_n=""
    local global_top_n=""
    local accepted_trend_granularity=""
    local force_city_mode="false"
    local project_info_mode="false"

    if [[ $# -eq 0 ]]; then
        # --- Интерактивный режим ---
        echo -e "${CYAN}=== Интерактивный режим ===${NC}"

        # Запрос ID проекта (5 цифр)
        while true; do
            echo -n "Введите 5-значный ID проекта: "
            read -r project_id
            if [[ "$project_id" =~ ^[0-9]{5}$ ]]; then
                break
            fi
            echo -e "${RED}Ошибка: ID должен состоять ровно из 5 цифр.${NC}"
        done

        # Выбор стадий
        echo ""
        echo "Доступные стадии выполнения:"
        echo "  1) IN_REVIEWS"
        echo "  2) IN_PROGRESS"
        echo "  3) ACCEPTED"
        echo "  4) REGISTERED"
        echo "  5) FAILED"
        echo -n "Введите номера стадий через запятую (по умолчанию: 1,2,3,4): "
        read -r stages_input
        if [[ -z "$stages_input" ]]; then
            stages_input="1,2,3,4"
        fi

        IFS=',' read -ra nums <<< "$stages_input"
        statuses_arr=()
        for n in "${nums[@]}"; do
            n="${n// /}"
            case "$n" in
                1) statuses_arr+=("IN_REVIEWS") ;;
                2) statuses_arr+=("IN_PROGRESS") ;;
                3) statuses_arr+=("ACCEPTED") ;;
                4) statuses_arr+=("REGISTERED") ;;
                5) statuses_arr+=("FAILED") ;;
                *) echo -e "${YELLOW}Предупреждение: неизвестный номер '$n', пропущен.${NC}" ;;
            esac
        done

        if [[ ${#statuses_arr[@]} -eq 0 ]]; then
            echo -e "${YELLOW}Стадии не выбраны, используются по умолчанию: IN_REVIEWS,IN_PROGRESS,ACCEPTED,REGISTERED${NC}"
            statuses_arr=("IN_REVIEWS" "IN_PROGRESS" "ACCEPTED" "REGISTERED")
        fi

        statuses_input=$(IFS=','; echo "${statuses_arr[*]}")
        echo -e "${BLUE}Выбранные стадии: $statuses_input${NC}"
        echo ""

        load_env
        info "🔐 Получаем токен..."
        token=$(get_token_cached)
        [[ -z "$token" || "$token" == "null" ]] && die "Ошибка получения токена"

        info "📋 Ищем участников проекта $project_id со статусами: $statuses_input ..."
        logins=$(get_unique_participants_for_statuses "$token" "$project_id" "$statuses_input" "") || die "Не удалось полностью загрузить участников"

        echo ""
        if [[ -z "$logins" ]]; then
            echo -e "${YELLOW}Студенты не найдены для проекта $project_id с указанными стадиями.${NC}"
        else
            count=$(echo "$logins" | grep -c .)
            echo -e "${GREEN}📊 Найдено студентов: $count${NC}"
            echo ""
            printf "%-4s %-20s\n" "№" "Логин"
            printf "%-4s %-20s\n" "----" "--------------------"
            echo "$logins" | nl -w4 -s" " | while read -r idx login; do
                printf "%-4s %-20s\n" "$idx" "$login"
            done
        fi

        exit 0
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p|--project-id)
                [[ $# -lt 2 ]] && die "-p/--project-id требует значение"
                project_id="$2"
                shift 2
                ;;
            -s|--statuses)
                [[ $# -lt 2 ]] && die "-s/--statuses требует значение"
                statuses_input="$2"
                shift 2
                ;;
            -c|--city)
                [[ $# -lt 2 ]] && die "-c/--city требует значение"
                city="$2"
                shift 2
                ;;
            --all-campuses)
                all_campuses_mode="true"
                shift
                ;;
            --include-excluded-campuses)
                include_excluded_campuses="true"
                shift
                ;;
            --compare-cities)
                [[ $# -lt 2 ]] && die "--compare-cities требует значение"
                compare_cities="$2"
                shift 2
                ;;
            -f|--format)
                [[ $# -lt 2 ]] && die "-f/--format требует значение"
                format="$2"
                shift 2
                ;;
            -q|--quiet)
                QUIET="true"
                shift
                ;;
            --fresh-token)
                NO_TOKEN_CACHE="true"
                shift
                ;;
            -u|--ufa-accepted-count)
                ufa_accepted_count_mode="true"
                shift
                ;;
            --project-info)
                project_info_mode="true"
                shift
                ;;
            --status-summary)
                status_summary_mode="true"
                shift
                ;;
            --top)
                [[ $# -lt 2 ]] && die "--top требует значение"
                top_n="$2"
                shift 2
                ;;
            --global-top)
                [[ $# -lt 2 ]] && die "--global-top требует значение"
                global_top_n="$2"
                shift 2
                ;;
            --accepted-trend)
                [[ $# -lt 2 ]] && die "--accepted-trend требует значение"
                accepted_trend_granularity="$2"
                shift 2
                ;;
            --force-city)
                force_city_mode="true"
                shift
                ;;
            -h|--help)
                print_help
                exit 0
                ;;
            *)
                die "Неизвестный аргумент: $1"
                ;;
        esac
    done

    # Валидация статусов: неизвестные — предупреждение, пустой список — ошибка
    local -a st_check=()
    IFS=',' read -r -a st_check <<< "$statuses_input"
    local -a st_trim=()
    local st
    for st in "${st_check[@]}"; do
        st="${st// /}"
        [[ -z "$st" ]] && continue
        case "$st" in
            REGISTERED|IN_PROGRESS|IN_REVIEWS|ACCEPTED|FAILED) ;;
            *) info "  ⚠️ Статус '$st' не входит в известные ($DEFAULT_STATUSES) — передаю как есть" ;;
        esac
        st_trim+=("$st")
    done
    if (( ${#st_trim[@]} == 0 )); then
        die "Пустой список статусов"
    fi
    statuses_input=$(IFS=','; echo "${st_trim[*]}")

    if [[ -z "$project_id" && -z "$global_top_n" ]]; then
        if [[ ! -t 0 ]]; then
            die "Укажите --project-id ID или --global-top N (stdin не терминал — интерактивный ввод отключен)"
        fi
        echo -n "Введите ID проекта: "
        read -r project_id
    fi

    if [[ -n "$project_id" && ! "$project_id" =~ ^[0-9]+$ ]]; then
        die "project-id должен быть числом"
    fi

    local project_name
    project_name=$(get_project_name "$project_id")

    case "$format" in
        plain|json|csv) ;;
        *) die "--format должен быть одним из: plain|json|csv" ;;
    esac

    if [[ "$include_excluded_campuses" == "true" ]]; then
        INCLUDE_EXCLUDED_CAMPUSES="true"
    fi

    local mode_count=0
    [[ "$project_info_mode" == "true" ]] && mode_count=$((mode_count + 1))
    [[ "$ufa_accepted_count_mode" == "true" ]] && mode_count=$((mode_count + 1))
    [[ "$status_summary_mode" == "true" ]] && mode_count=$((mode_count + 1))
    [[ -n "$top_n" ]] && mode_count=$((mode_count + 1))
    [[ -n "$global_top_n" ]] && mode_count=$((mode_count + 1))
    [[ -n "$accepted_trend_granularity" ]] && mode_count=$((mode_count + 1))
    [[ -n "$compare_cities" ]] && mode_count=$((mode_count + 1))

    if (( mode_count > 1 )); then
        die "Укажите только один режим: --project-info | -u | --status-summary | --top N | --global-top N | --accepted-trend day|week | --compare-cities"
    fi

    if [[ -z "$project_id" && -z "$global_top_n" ]]; then
        die "Укажите --project-id ID или используйте режим --global-top N"
    fi

    if [[ "$ufa_accepted_count_mode" == "true" ]]; then
        city="Ufa"
        statuses_input="ACCEPTED"
    fi

    if [[ "$status_summary_mode" == "true" ]]; then
        if [[ "$all_campuses_mode" == "true" && -n "$city" ]]; then
            die "Для --status-summary используйте только один вариант: --city или --all-campuses"
        fi
        if [[ "$all_campuses_mode" != "true" && -z "$city" ]]; then
            die "Для --status-summary нужен --city или --all-campuses"
        fi
    fi

    if [[ -n "$top_n" || -n "$accepted_trend_granularity" ]]; then
        [[ -z "$city" ]] && die "Для этого режима нужен --city"
    fi

    if [[ "$all_campuses_mode" == "true" && "$status_summary_mode" != "true" ]]; then
        die "--all-campuses поддерживается только вместе с --status-summary"
    fi

    if [[ -n "$top_n" && ( ! "$top_n" =~ ^[0-9]+$ || "$top_n" == "0" ) ]]; then
        die "--top должен быть положительным числом"
    fi

    if [[ -n "$global_top_n" && ( ! "$global_top_n" =~ ^[0-9]+$ || "$global_top_n" == "0" ) ]]; then
        die "--global-top должен быть положительным числом"
    fi

    if [[ -n "$accepted_trend_granularity" && "$accepted_trend_granularity" != "day" && "$accepted_trend_granularity" != "week" ]]; then
        die "--accepted-trend должен быть day или week"
    fi

    load_env

    info "🔐 Получаем токен..."
    local token
    token=$(get_token_cached)
    [[ -z "$token" || "$token" == "null" ]] && die "Ошибка получения токена"

    if [[ "$project_info_mode" == "true" ]]; then
        [[ -n "$project_id" ]] || die "Для --project-info нужен --project-id"
        [[ -z "$city" && "$all_campuses_mode" != "true" && -z "$compare_cities" ]] || die "--project-info нельзя совмещать с выбором кампуса"
        local project_json
        project_json=$(api_get "$token" "/projects/$project_id") || die "Не удалось получить проект $project_id"
        if ! printf '%s' "$project_json" | jq -e --arg id "$project_id" 'type == "object" and (.projectId | tostring == $id) and (.title | type == "string") and (.description | type == "string") and (.durationHours | type == "number") and (.type | type == "string")' >/dev/null 2>&1; then
            die "API вернул неверную структуру проекта $project_id"
        fi
        case "$format" in
            json) printf '%s\n' "$project_json" | jq '{projectId, title, description, type, durationHours, xp, courseId}' ;;
            csv) printf 'project_id,title,type,duration_hours,xp,course_id,description\n'
                 printf '%s\n' "$project_json" | jq -r '[.projectId, .title, .type, .durationHours, (.xp // ""), (.courseId // ""), .description] | @csv' ;;
            plain) printf '%s\n' "$project_json" | jq -r '"ID: \(.projectId)\nНазвание: \(.title)\nТип: \(.type)\nДлительность: \(.durationHours) ч\nXP: \(.xp // "нет данных")\nКурс: \(.courseId // "нет данных")\nОписание: \(.description)"' ;;
        esac
        return 0
    fi

    # Mode: compare cities
    if [[ -n "$compare_cities" ]]; then
        local tmp_compare
        new_tmp tmp_compare

        IFS=',' read -r -a cities <<< "$compare_cities"
        local city_name city_resolved city_campus_id total_count accepted_count rate
        for city_name in "${cities[@]}"; do
            city_name="$(echo "$city_name" | xargs)"
            if ! city_resolved=$(get_campus_id_by_city "$token" "$city_name" "false"); then
                die "Не удалось получить список кампусов (API вернул невалидный ответ)"
            fi
            city_campus_id="${city_resolved%%|*}"
            if [[ -z "$city_campus_id" ]]; then
                echo "$city_name|0|0|0" >> "$tmp_compare"
                continue
            fi

            total_count=$(get_unique_participants_for_statuses "$token" "$project_id" "$DEFAULT_STATUSES" "$city_campus_id") || die "Не удалось полностью загрузить участников"

            total_count=$(printf '%s\n' "$total_count" | grep -c . || true)
            accepted_count=$(get_unique_participants_for_statuses "$token" "$project_id" "ACCEPTED" "$city_campus_id") || die "Не удалось полностью загрузить участников"
            accepted_count=$(printf '%s\n' "$accepted_count" | grep -c . || true)

            if (( total_count == 0 )); then
                rate="0"
            else
                rate=$(awk -v a="$accepted_count" -v t="$total_count" 'BEGIN { printf "%.2f", (a/t)*100 }')
            fi

            echo "$city_name|$total_count|$accepted_count|$rate" >> "$tmp_compare"
        done

        emit_compare_cities "$project_id" "$format" "$tmp_compare" "$project_name"
        exit 0
    fi

    local campus_id=""
    local campus_name_resolved=""
    if [[ -n "$city" ]]; then
        local campus_resolved
        if [[ "$force_city_mode" == "true" ]]; then
            if ! campus_resolved=$(get_campus_id_by_city "$token" "$city" "true"); then
                die "Не удалось получить список кампусов (API вернул невалидный ответ)"
            fi
            [[ -z "$campus_resolved" ]] && die "Город '$city' не найден среди доступных кампусов"
        else
            if ! campus_resolved=$(get_campus_id_by_city "$token" "$city" "$include_excluded_campuses"); then
                die "Не удалось получить список кампусов (API вернул невалидный ответ)"
            fi
            [[ -z "$campus_resolved" ]] && die "Город '$city' не найден среди доступных кампусов (или исключен)"
        fi
        campus_id="${campus_resolved%%|*}"
        campus_name_resolved="${campus_resolved#*|}"
    fi

    # Mode: global top by points (all participants, not tied to project)
    if [[ -n "$global_top_n" ]]; then
        local tmp_logins tmp_metrics campus_line campus_id_i campus_name_i
        local campus_tmp total_logins processed_login_file start_time eta_pid
        new_tmp tmp_logins
        new_tmp tmp_metrics

        if [[ -z "$campus_id" ]]; then
            local campuses_file
            new_tmp campuses_file
            get_all_campuses "$token" > "$campuses_file" || die "Не удалось получить кампусы"
        fi
        if [[ -n "$campus_id" ]]; then
            info "📚 Сбор участников кампуса '$city'..."
            get_participants_by_campus "$token" "$campus_id" > "$tmp_logins" || die "Не удалось полностью загрузить кампус"
            info "  ✓ Собрано логинов: $(wc -l < "$tmp_logins")"
        else
            info "🏫 Сбор участников по всем кампусам (без исключённых)..."
            while IFS= read -r campus_line; do
                campus_id_i="${campus_line%%|*}"
                campus_name_i="${campus_line#*|}"
                if is_campus_excluded "$campus_id_i" || is_campus_name_excluded "$campus_name_i"; then
                    continue
                fi
                info "  ↳ Кампус: $campus_name_i"
                new_tmp campus_tmp
                get_participants_by_campus "$token" "$campus_id_i" > "$campus_tmp" || die "Не удалось полностью загрузить кампус $campus_name_i"
                info "    найдено: $(wc -l < "$campus_tmp")"
                cat "$campus_tmp" >> "$tmp_logins"
            done < "$campuses_file"
        fi

        sort -u "$tmp_logins" -o "$tmp_logins"
        total_logins=$(wc -l < "$tmp_logins")
        info "👥 Уникальных логинов для расчета: $total_logins"

        info "📈 Считаем pointsTotal по участникам (16 потоков)..."
        export token
        export BASE_URL
        export tmp_metrics
        export QUIET
        export -f api_get info
        process_login_points() {
            local login="$1"
            local points=""
            local response attempt
            for attempt in 1 2 3 4; do
                response=$(api_get "$token" "/participants/$login")
                points=$(echo "$response" | jq -er '.expValue | select(type == "number")' 2>/dev/null)
                if [[ -n "$points" ]]; then
                    break
                fi
                if echo "$response" | grep -qi "Too many requests"; then
                    sleep "$attempt"
                else
                    sleep 1
                fi
            done
            [[ -n "$points" ]] || return 1
            echo "$login|$points" >> "$tmp_metrics"
        }
        export -f process_login_points

        new_tmp processed_login_file
        start_time=$(date +%s)

        # Фоновый процесс для ETA
        (
            while true; do
                sleep 1
                processed_login=$(wc -l < "$processed_login_file")
                now_time=$(date +%s)
                elapsed=$((now_time - start_time))
                if (( processed_login > 0 )); then
                    avg_time=$(awk "BEGIN {print $elapsed/$processed_login}")
                    remaining=$((total_logins - processed_login))
                    eta_sec=$(awk "BEGIN {print int($remaining * $avg_time)}")
                    eta_min=$((eta_sec / 60))
                    eta_sec_rem=$((eta_sec % 60))
                    eta_disp=$(printf "%02d:%02d" "$eta_min" "$eta_sec_rem")
                else
                    eta_disp="--:--"
                fi
                printf "\r  ⏳ Обработано: %d/%d | ETA: %s" "$processed_login" "$total_logins" "$eta_disp" >&2
                if (( processed_login >= total_logins )); then
                    break
                fi
            done
        ) &
        eta_pid=$!

        xargs -r -P 16 -I{} bash -c 'process_login_points "$1"; rc=$?; echo 1 >> "$2"; exit $rc' _ {} "$processed_login_file" < "$tmp_logins"

        workers_status=$?
        wait "$eta_pid"
        echo >&2
        (( workers_status == 0 )) || die "Не все метрики загружены; рейтинг не опубликован"

        case "$format" in
            plain)
                echo "Топ $global_top_n по pointsTotal"
                printf "%-20s %-12s\n" "Логин" "PointsTotal"
                printf "%-20s %-12s\n" "--------------------" "------------"
                sort -t'|' -k2,2nr "$tmp_metrics" | head -n "$global_top_n" | while IFS='|' read -r login p; do
                    printf "%-20s %-12s\n" "$login" "$p"
                done
                ;;
            json)
                jq -Rn --arg city "$city" --argjson top "$global_top_n" '
                    [inputs | split("|") | {login: .[0], pointsTotal: (.[1]|tonumber? // 0)}]
                    | sort_by(.pointsTotal)
                    | reverse
                    | .[:$top]
                    | {scope: (if $city == "" then "all_campuses" else "city" end), city: (if $city == "" then null else $city end), top: $top, byPointsTotal: .}
                ' < "$tmp_metrics"
                ;;
            csv)
                echo "rank,login,points_total"
                sort -t'|' -k2,2nr "$tmp_metrics" | head -n "$global_top_n" | nl -w1 -s'|' | while IFS='|' read -r rank login p; do
                    echo "$rank,$login,${p:-0}"
                done
                ;;
        esac

        exit 0
    fi

    # Mode: status summary by city or all campuses
    if [[ "$status_summary_mode" == "true" ]]; then
        local status tmp_summary count
        new_tmp tmp_summary
        local -a status_arr=()
        IFS=',' read -r -a status_arr <<< "$DEFAULT_STATUSES"

        if [[ "$all_campuses_mode" == "true" ]]; then
            local campus_line campus_id_i campus_name_i campuses_file
            new_tmp campuses_file
            get_active_campuses "$token" > "$campuses_file" || die "Не удалось получить кампусы"
            while IFS= read -r campus_line; do
                campus_id_i="${campus_line%%|*}"
                campus_name_i="${campus_line#*|}"

                for status in "${status_arr[@]}"; do
                    count=$(get_unique_participants_for_statuses "$token" "$project_id" "$status" "$campus_id_i") || die "Не удалось полностью загрузить участников"
                    count=$(printf '%s\n' "$count" | grep -c . || true)
                    echo "$campus_name_i|$status|$count" >> "$tmp_summary"
                done
            done < "$campuses_file"

            emit_all_campuses_status_summary "$project_id" "$format" "$tmp_summary" "$project_name"
        else
            for status in "${status_arr[@]}"; do
                count=$(get_unique_participants_for_statuses "$token" "$project_id" "$status" "$campus_id") || die "Не удалось полностью загрузить участников"
                count=$(printf '%s\n' "$count" | grep -c . || true)
                echo "$status|$count" >> "$tmp_summary"
            done

            emit_status_summary "$project_id" "$city" "$format" "$tmp_summary" "$project_name"
        fi

        exit 0
    fi

    # Gather participants for active mode/default
    info "📋 Поиск участников проекта $project_id..."
    local participants_file
    new_tmp participants_file
    get_unique_participants_for_statuses "$token" "$project_id" "$statuses_input" "$campus_id" > "$participants_file" || die "Не удалось полностью загрузить участников"

    # Mode: Ufa accepted count
    if [[ "$ufa_accepted_count_mode" == "true" ]]; then
        local ufa_count
        ufa_count=$(wc -l < "$participants_file")
        if [[ -n "$project_name" ]]; then
            emit_count_result "Окончивших проект $project_id ($project_name) в Ufa" "$ufa_count" "$format"
        else
            emit_count_result "Окончивших проект $project_id в Ufa" "$ufa_count" "$format"
        fi
        exit 0
    fi

    # Mode: top metrics in city
    if [[ -n "$top_n" ]]; then
        local tmp_metrics
        new_tmp tmp_metrics

        info "📈 Считаем pointsTotal и avgSkill по участникам (16 потоков)..."
        # FIX 1: раньше эти функции не экспортировались в xargs-потоки —
        # метрики были пустыми, а json падал на tonumber
        export token
        export BASE_URL
        export tmp_metrics
        export QUIET
        export -f api_get info get_participant_points_total get_participant_avg_skill
        process_login_metrics() {
            local login="$1"
            local points_total avg_skill
            points_total=$(get_participant_points_total "$token" "$login") || return 1
            avg_skill=$(get_participant_avg_skill "$token" "$login") || return 1
            echo "$login|$points_total|$avg_skill" >> "$tmp_metrics"
        }
        export -f process_login_metrics

        local total_logins processed_login_file start_time eta_pid
        total_logins=$(wc -l < "$participants_file")
        new_tmp processed_login_file
        start_time=$(date +%s)

        (
            while true; do
                sleep 1
                processed_login=$(wc -l < "$processed_login_file")
                now_time=$(date +%s)
                elapsed=$((now_time - start_time))
                if (( processed_login > 0 )); then
                    avg_time=$(awk "BEGIN {print $elapsed/$processed_login}")
                    remaining=$((total_logins - processed_login))
                    eta_sec=$(awk "BEGIN {print int($remaining * $avg_time)}")
                    eta_min=$((eta_sec / 60))
                    eta_sec_rem=$((eta_sec % 60))
                    eta_disp=$(printf "%02d:%02d" "$eta_min" "$eta_sec_rem")
                else
                    eta_disp="--:--"
                fi
                printf "\r  ⏳ Обработано: %d/%d | ETA: %s" "$processed_login" "$total_logins" "$eta_disp" >&2
                if (( processed_login >= total_logins )); then
                    break
                fi
            done
        ) &
        eta_pid=$!

        xargs -r -P 16 -I{} bash -c 'process_login_metrics "$1"; rc=$?; echo 1 >> "$2"; exit $rc' _ {} "$processed_login_file" < "$participants_file"

        workers_status=$?
        wait "$eta_pid"
        echo >&2
        (( workers_status == 0 )) || die "Не все метрики загружены; рейтинг не опубликован"

        case "$format" in
            plain)
                echo "Топ $top_n по pointsTotal"
                printf "%-20s %-12s\n" "Логин" "PointsTotal"
                printf "%-20s %-12s\n" "--------------------" "------------"
                sort -t'|' -k2,2nr "$tmp_metrics" | head -n "$top_n" | while IFS='|' read -r login p _ _; do
                    printf "%-20s %-12s\n" "$login" "${p:-0}"
                done

                echo
                echo "Топ $top_n по avgSkill"
                printf "%-20s %-12s\n" "Логин" "AvgSkill"
                printf "%-20s %-12s\n" "--------------------" "------------"
                sort -t'|' -k3,3nr "$tmp_metrics" | head -n "$top_n" | while IFS='|' read -r login _ s _; do
                    printf "%-20s %-12s\n" "$login" "$(awk -v v="${s:-0}" 'BEGIN{printf "%.2f", v+0}')"
                done
                ;;
            json)
                jq -Rn --arg projectId "$project_id" --arg city "$city" --argjson top "$top_n" '
                    [inputs | split("|") | {login: .[0], pointsTotal: (.[1]|tonumber? // 0), avgSkill: (.[2]|tonumber? // 0)}] as $all
                    | {
                        projectId: $projectId,
                        city: $city,
                        top: $top,
                        byPointsTotal: ($all | sort_by(.pointsTotal) | reverse | .[:$top]),
                        byAvgSkill: ($all | sort_by(.avgSkill) | reverse | .[:$top])
                      }
                ' < "$tmp_metrics"
                ;;
            csv)
                echo "metric,rank,login,value"
                sort -t'|' -k2,2nr "$tmp_metrics" | head -n "$top_n" | nl -w1 -s'|' | while IFS='|' read -r rank login p _; do
                    echo "pointsTotal,$rank,$login,${p:-0}"
                done
                sort -t'|' -k3,3nr "$tmp_metrics" | head -n "$top_n" | nl -w1 -s'|' | while IFS='|' read -r rank login _ s; do
                    echo "avgSkill,$rank,$login,${s:-0}"
                done
                ;;
        esac

        exit 0
    fi

    # Mode: accepted trend
    if [[ -n "$accepted_trend_granularity" ]]; then
        local tmp_accepted tmp_trend login completed_at key
        new_tmp tmp_accepted
        new_tmp tmp_trend

        get_unique_participants_for_statuses "$token" "$project_id" "ACCEPTED" "$campus_id" > "$tmp_accepted" || die "Не удалось полностью загрузить участников"

        while IFS= read -r login; do
            [[ -z "$login" ]] && continue
            completed_at=$(get_project_completion_datetime "$token" "$login" "$project_id")
            [[ -z "$completed_at" || "$completed_at" == "null" ]] && continue

            if [[ "$accepted_trend_granularity" == "day" ]]; then
                key="${completed_at%%T*}"
            else
                key=$(date -u -d "$completed_at" +"%G-W%V" 2>/dev/null)
            fi
            [[ -n "$key" ]] && echo "$key" >> "$tmp_trend"
        done < "$tmp_accepted"

        sort "$tmp_trend" | uniq -c | awk '{print $2"|"$1}' > "$tmp_trend.counts"
        TMP_FILES+=("$tmp_trend.counts")

        case "$format" in
            plain)
                echo "Динамика завершений (ACCEPTED) | Проект: $project_id | Город: $city | Шаг: $accepted_trend_granularity"
                printf "%-12s %10s\n" "Период" "Количество"
                printf "%-12s %10s\n" "------------" "----------"
                while IFS='|' read -r period cnt; do
                    printf "%-12s %10d\n" "$period" "$cnt"
                done < "$tmp_trend.counts"
                ;;
            json)
                jq -Rn --arg projectId "$project_id" --arg city "$city" --arg granularity "$accepted_trend_granularity" '
                    [inputs | split("|") | {period: .[0], count: (.[1]|tonumber)}]
                    | {projectId: $projectId, city: $city, granularity: $granularity, trend: .}
                ' < "$tmp_trend.counts"
                ;;
            csv)
                echo "project_id,city,granularity,period,count"
                while IFS='|' read -r period cnt; do
                    echo "$project_id,$city,$accepted_trend_granularity,$period,$cnt"
                done < "$tmp_trend.counts"
                ;;
        esac

        exit 0
    fi

    # Default mode: таблица логинов с кампусами.
    # При --city кампус уже известен (campus_name_resolved) — без N+1 запросов;
    # без --city работает кэш, заполненный при сборе участников.
    local final_list_file
    new_tmp final_list_file

    local login campus_info campus_name_student
    while IFS= read -r login; do
        [[ -z "$login" ]] && continue

        if [[ -n "$campus_id" ]]; then
            campus_name_student="$campus_name_resolved"
        elif [[ -n "${CAMPUS_CACHE[$login]+x}" ]]; then
            campus_name_student="${CAMPUS_CACHE[$login]#*|}"
        else
            campus_info=$(get_student_campus "$token" "$login") || return 1
            CAMPUS_CACHE["$login"]="$campus_info"
            campus_name_student="${campus_info#*|}"
        fi
        echo "$login|$campus_name_student" >> "$final_list_file"
    done < "$participants_file"

    sort -u "$final_list_file" > "$final_list_file.sorted"
    TMP_FILES+=("$final_list_file.sorted")
    local total_filtered
    total_filtered=$(wc -l < "$final_list_file.sorted")

    case "$format" in
        plain)
            printf "%-4s %-20s %-30s\n" "№" "Логин" "Кампус"
            printf "%-4s %-20s %-30s\n" "--" "--------------------" "------------------------------"
            nl -w1 -s'|' "$final_list_file.sorted" | while IFS='|' read -r idx row; do
                login="${row%%|*}"
                campus="${row#*|}"
                printf "%-4d %-20s %-30s\n" "$idx" "$login" "$campus"
            done
            printf "%-4s %-20s %-30s\n" "--" "--------------------" "------------------------------"
            printf '%b📊 Всего: %d студентов%b\n' "$GREEN" "$total_filtered" "$NC"
            ;;
        json)
            jq -Rn --argjson total "$total_filtered" '
                [inputs | split("|") | {login: .[0], campus: .[1]}] as $rows
                | {total: $total, students: $rows}
            ' < "$final_list_file.sorted"
            ;;
        csv)
            echo "login,campus"
            while IFS='|' read -r login campus; do
                printf "%s,%s\n" "$login" "$campus"
            done < "$final_list_file.sorted"
            ;;
    esac
}

main "$@"
