# peer-poller — сервис мониторинга статусов проектов 21-school

Автоматический опрос статусов проектов выбранной группы пиров и уведомления в
Telegram при каждом изменении (IN_PROGRESS → IN_REVIEWS → ACCEPTED, новые/исчезнувшие
проекты, добавление/удаление пиров из списка).

Дата развёртывания: 2026-10-05. Сервер: Oracle Cloud Always Free (E2.1.Micro, ca-toronto-1).

---

## Состав

| Файл | Назначение |
|---|---|
| `peer_poller.sh` | Поллер: снимок проектов всех пиров, diff, события, Telegram |
| `peers.txt` | Список логинов (по одному на строку; `#`-комментарии поддерживаются) |
| `students_v4.sh` | Исходный скрипт (API/аутентификация 21-school, из которого вырос поллер) |
| `install-server.sh` | Развёртывание на VPS: зависимости, файлы в /opt/peer-poller, systemd-юниты |
| `deploy/peer-poller.service` | Системный systemd-юнит (Type=oneshot) |
| `deploy/peer-poller.timer` | Таймер: каждые 10 минут, Persistent=true |
| `state/peers_state.tsv` | Текущий снимок: `login \t project_id \t status \t title \t last_seen` |
| `state/peers_history.log` | Append-only журнал всех событий |

### Настройки (переменные окружения / `.env`)
- `S21_USERNAME`, `S21_PASSWORD` — учётка 21-school (токен API, кэш `~/.cache/s21/token.json`)
- `TG_BOT_TOKEN`, `TG_CHAT_ID` — Telegram-бот и чат (без токена уведомления отключены)
- `PEERS_FILE` (по умолч. `<скрипт>/peers.txt`), `STATE_DIR` (по умолч. `<скрипт>/state`),
  `POLL_INTERVAL` (по умолч. 600 с, только для `--loop`)

### Режимы
```bash
./peer_poller.sh            # один цикл (для systemd timer / cron)
./peer_poller.sh --loop     # демон-режим (цикл + сон POLL_INTERVAL + джиттер)
./peer_poller.sh --show     # активные проекты (IN_PROGRESS/IN_REVIEWS/ACCEPTED)
./peer_poller.sh --reset    # сбросить baseline
./peer_poller.sh --test-tg  # тестовое сообщение в Telegram
./peer_poller.sh --help
```

### Логика событий
Каждый цикл: `/participants/{login}/projects` (limit=500, пагинация) для всех пиров →
полный снимок. Diff с прошлым снимком:
- `CHANGED` — сменился статус конкретного проекта (`IN_REVIEWS -> ACCEPTED` и т.п.)
- `NEW` — проект появился у пира
- `GONE` — проект исчез у пира
- `PEER_ADDED` — пир добавлен в peers.txt (одно событие на пира, без 600+ NEW)
- `PEER_REMOVED` — пир удалён из peers.txt

State обновляется атомарно и **только если успешно загрузились все пиры**.
При событиях — одно Telegram-сообщение за цикл (лимит 4096 симв., обрезаем с пометкой).

---

## Локальный запуск (на домашней машине)

```bash
cd /home/maxkram/poller
./peer_poller.sh            # на текущих peers.txt
./peer_poller.sh --show
```
systemd user-юниты (на домашней машине):
```bash
systemctl --user enable --now peer-poller.timer   # каждые 10 мин (linger включён)
systemctl --user list-timers | grep peer
systemctl --user disable --now peer-poller.timer  # выключить, если ведёт сервер
```

---

## Telegram: как завести бота и получить chat_id

1. **@BotFather → /newbot** → имя/username → получить `TG_BOT_TOKEN` (`123456:ABC-...`).
2. **chat_id личного чата** — любой из способов:
   - бот **@userinfobot**: найти через **глобальный поиск** в Telegram (не писать
     «@userinfobot» внутри чата другого бота!), Start → бот пришлёт числовой ID;
   - **BotFather → /newchatid** → прислать свой @username → ответит chat id;
   - через API: написать своему боту любое сообщение и:
     `curl -s 'https://api.telegram.org/bot<TOKEN>/getUpdates' | jq '.result[].message.chat.id'`
3. Для группы: бот добавляется в группу, chat_id отрицательный
   (узнать тем же `getUpdates` от сообщения в группе).
4. Проверка: `./peer_poller.sh --test-tg`

---

## Бесплатный сервер: Oracle Cloud Always Free

Лимиты (на дату 2026-10):
- VM.Standard.A1.Flex (ARM): 1500 OCPU-ч + 9000 ГБ-ч в месяц (= 2 OCPU/12 ГБ постоянно)
- VM.Standard.E2.1.Micro (AMD): 2 инстанса постоянно
- 200 ГБ блок-хранилища, минимум boot volume 47 ГБ

### Создание инстанса (консоль)
1. cloud.oracle.com → регион привязан (home region, для нас ca-toronto-1).
2. Compute → Instances → **Create an instance**.
3. Image: **Canonical Ubuntu 24.04**; Availability Domain: AD-1 (если «Out of host
   capacity» на A1.Flex → другой AD или сразу E2.1.Micro).
4. Shape: **VM.Standard.E2.1.Micro** (1 OCPU/1 ГБ — для поллера хватает) или A1.Flex 1/2.
   ⚠️ Только метка «Always Free-eligible», иначе будет биллинг.
5. Networking: Create new VCN (default 10.0.0.0/16), new **public** subnet,
   ☑ **Automatically assign public IPv4 address** (в одностраничном создании VCN
   публичный IP иногда не проставляется — тогда после запуска: Instance →
   Instance access → «Add public IP» → ephemeral, «accessible from the internet»).
6. SSH: Generate a key pair → **скачать приватный ключ** (показывается один раз!)
   или вставить именно **одну строку** своего .pub (два склеенных ключа = невалидный,
   зайти не получится; ремонт через Serial Console: root/`oracle`,
   правка `/home/ubuntu/.ssh/authorized_keys`).
7. Storage: дефолтный boot volume (47 ГБ).
8. Create → RUNNING за 2–5 мин → запомнить **Public IP**.

---

## Развёртывание на сервере

```bash
# С ДОМАШНЕЙ МАШИНЫ (не с сервера!), из /home/maxkram/poller:
export KEY=<путь к приватному ключу>
export IP=<публичный IP инстанса>

scp -i "$KEY" install-server.sh peer_poller.sh peers.txt ubuntu@$IP:/tmp/
scp -i "$KEY" -r deploy ubuntu@$IP:/tmp/
ssh -i "$KEY" ubuntu@$IP 'cd /tmp && sudo bash install-server.sh'
```

Скрипт: apt (jq, curl, ca-certificates) → файлы в `/opt/peer-poller/` →
`/etc/systemd/system/peer-poller.{service,timer}` → enable+start таймера.

```bash
# На сервере:
sudo nano /opt/peer-poller/.env      # S21_USERNAME, S21_PASSWORD, TG_BOT_TOKEN, TG_CHAT_ID
curl -sI https://api.telegram.org | head -1                # HTTP/1.1 200 OK?
sudo /opt/peer-poller/peer_poller.sh --test-tg             # тест Telegram
sudo /opt/peer-poller/peer_poller.sh --once                # baseline (без событий)
sudo journalctl -u peer-poller -f                          # живой лог
```

---

## Обновление списка пиров на сервере

**Важно:** обновляйте и `peers.txt`, и (если скрипт менялся) `peer_poller.sh` —
иначе при добавлении пиров первый цикл может выдать сотни NEW-событий
(в актуальном скрипте это подавляется: одно событие PEER_ADDED на пира).

```bash
# С ДОМАШНЕЙ МАШИНЫ:
export KEY=<путь к ключу>  IP=<IP>
cd /home/maxkram/poller
scp -i "$KEY" peers.txt peer_poller.sh ubuntu@$IP:/tmp/
ssh -i "$KEY" ubuntu@$IP '
  sudo cp /tmp/peers.txt /tmp/peer_poller.sh /opt/peer-poller/ &&
  sudo /opt/peer-poller/peer_poller.sh --once'
# в Telegram придёт: "+ <пир>: добавлен в peers.txt (N проектов)"
```

Быстрая правка без scp (если меняете только пиров):
```bash
sudo nano /opt/peer-poller/peers.txt   # на сервере
sudo /opt/peer-poller/peer_poller.sh --once
```

> При удалении пира из списка придёт PEER_REMOVED, его строки уйдут из state.

## Обновление скрипта/юнитов на сервере (если менялись)
```bash
scp -i "$KEY" peer_poller.sh deploy/peer-poller.service ubuntu@$IP:/tmp/
ssh -i "$KEY" ubuntu@$IP '
  sudo cp /tmp/peer_poller.sh /opt/peer-poller/ &&
---

## Эксплуатация (на сервере)

```bash
sudo journalctl -u peer-poller -f                       # лог systemd
sudo tail -f /opt/peer-poller/state/peers_history.log   # история событий
sudo /opt/peer-poller/peer_poller.sh --show             # активные проекты
sudo /opt/peer-poller/peer_poller.sh --reset            # новый baseline (сброс)
sudo systemctl status peer-poller.timer                 # статус таймера
sudo systemctl list-timers | grep peer                  # следующий запуск
```

- Интервал: править `OnUnitInactiveSec=` в `/etc/systemd/system/peer-poller.timer`
  + `sudo systemctl daemon-reload`.
- Полная остановка: `sudo systemctl stop peer-poller.timer`.
- Публичный IP переживает reboot/stop; меняется только при пересоздании VNIC/инстанса.

---

## Web UI (управление пирами из браузера)

Лёгкий web-интерфейс (`peers_web.py`, только stdlib Python, без зависимостей):
таблица пиров со статистикой из снимка (всего проектов, активных IN_PROGRESS/
IN_REVIEWS/ACCEPTED), добавление (логин или список через запятую/пробел),
удаление выбранных, ручной опрос «сейчас», последние события. Изменение списка
по умолчанию сразу запускает `peer_poller.sh --once` → в Telegram приходят
PEER_ADDED/PEER_REMOVED.

### Доступ
```
http://40.233.118.196:8080/p/3gnRN2Ws-ZttcOA5YZ68GQ
```
- Сервер слушает `0.0.0.0:8080` (`WEB_PORT=8080`; опционально `WEB_BIND`).
- Токен — содержимое `/opt/peer-poller/web_token` (600). Сменить: на сервере
  `sudo python3 -c "import secrets;print(secrets.token_urlsafe(16))"` →
  записать в web_token → `sudo systemctl restart peer-poller-web`.
- Юнит на сервере: `peer-poller-web.service` (Type=simple, Restart=on-failure).
- Статус: `sudo systemctl status peer-poller-web`, лог: `sudo journalctl -u peer-poller-web -f`.

> Сетевой нюанс: из корпоративной сети (Sber) наружу открыт узкий набор портов
> (проверено: до VPS гарантированно открыт 22; web-порты время от времени
> отрезаются). Если браузер не открывает страницу — попробуйте с другой сети
> (мобильный интернет и т.п.) или временно поднять SSH-туннель:
> `ssh -N -L 127.0.0.1:8090:127.0.0.1:8080 -i ~/.ssh/peer-poller-vps ubuntu@40.233.118.196`
> и откройте `http://127.0.0.1:8090/p/<токен>`.

## MTProto-прокси для Telegram (alexbers/mtprotoproxy)

Отдельный Oracle Always Free-инстанс для прокси-сервера Telegram (MTProto).
Трафик идёт через proxy → Telegram не блокирует и не тормозит с прокси.
Используется **отдельный** сервер, а не прод-поллер: IP прокси целят DPI и
могут резать сеть — не тащим это на прод-сервер поллера.

### ✅ РАЗВЕРНУТО (10.10.2026) — работает
- Инстанс: `instance-20261008-1657`, Oracle Linux 9.8, E2.1.Micro, ca-toronto-1.
  Публичный IP **`147.5.125.142`**, user `opc`, key `~/.ssh/proxy-mtproxy`.
- Секрет (TLS-маска, префикс `ee` + hex-код домена):
  `eefd2de510abe9c7040340256554000b1a7777772e676f6f676c652e636f6d`
- Ссылки:
  - `tg://proxy?server=147.5.125.142&port=8443&secret=eefd2de510abe9c7040340256554000b1a7777772e676f6f676c652e636f6d`
  - `https://t.me/proxy?server=147.5.125.142&port=8443&secret=eefd2de510abe9c7040340256554000b1a7777772e676f6f676c652e636f6d`
- Проверка извне (pollerVPS 40.233.118.196): 8443 TCP открыт, прокси отдаёт
  сертификат Google (`subject=CN=www.google.com`, verify ok) → маскировка и
  внешний доступ работают.
- Доступ SSH: прямой `ssh opc@147.5.125.142` с домашней **вешается на banner**
  (DPI-срез). Рабочий путь — через jump (см. «Установка» ниже).

### Состав
- `install-mtproxy.sh` — установка: зависимости, код в `/opt/mtproto-proxy`, `config.py`,
  systemd-юнит, печать ссылок для клиентов.
- `deploy/mtproxy.service` — systemd-юнит (Type=simple, Restart=on-failure).
- `mtproxy-links.sh` — показать ссылку (`--regen` — сменить секрет и перезапустить).

### Новый инстанс Oracle (Always Free, рекомендую)
1. **Create VM instance** → Image: **Ubuntu 24.04** (проще) или **Oracle Linux 9**
   (скрипт сам определяет ОС: Ubuntu→apt, Oracle Linux→dnf+firewalld) / Shape:
   **E2.1.Micro** (1 vCPU; RAM формально 1 ГБ, реально доступно ~500 МБ — см. OOM ниже). Если нужен ARM — A1.Flex, но в AD-1
   ca-toronto часто «Out of capacity» → E2.1.Micro.
2. Включить чекбокс **Assign a public IPv4 address** (иначе после создания IP нет).
3. **VCN → Subnet → Security List → Add Ingress Rules**:
   - Source CIDR `0.0.0.0/0`, IP Protocol **TCP**, Destination port **8443**
   - Source CIDR `0.0.0.0/0`, IP Protocol **UDP**, Destination port **8443** (опционально — alexbers/mtprotoproxy работает по TCP)
   - (порт `22` TCP открыть для SSH, если закрыт)
4. Добавить SSH-ключ (публичную часть `~/.ssh/proxy-mtproxy.pub` и т.п.).
5. Дождаться Running и публичного IP.

> Oracle Linux: `firewalld` открывает 8443 сам скрипт; у пользователя входа
> username **`opc`**. Ubuntu: username **`ubuntu`**.

### Установка (с домашней машины, скрипты копируются scp)
```bash
# Прямой SSH к прокси-инстансу с домашней сети часто вешает DPI (banner
# зависает). Обойти: прыжок через pollerVPS (40.233.118.196, ubuntu@,
# ключ ~/.ssh/peer-poller-vps). Ключ к самому прокси: ~/.ssh/proxy-mtproxy, user opc.
J="-J ubuntu@40.233.118.196"
# проверка доступа:
ssh -i ~/.ssh/proxy-mtproxy $J opc@<IP-прокси> 'whoami'

# 1) скопировать скрипты (с домашней, через jump):
ssh -i ~/.ssh/proxy-mtproxy $J opc@<IP-прокси> 'mkdir -p /tmp/deploy'
scp -i ~/.ssh/proxy-mtproxy $J /home/maxkram/poller/install-mtproxy.sh opc@<IP-прокси>:/tmp/install-mtproxy.sh
scp -i ~/.ssh/proxy-mtproxy $J /home/maxkram/poller/deploy/mtproxy.service opc@<IP-прокси>:/tmp/deploy/mtproxy.service
# (скрипт ищет юнит в $(dirname install)/deploy/mtproxy.service)
# 2) установить:
ssh -i ~/.ssh/proxy-mtproxy $J opc@<IP-прокси> 'sudo bash /tmp/install-mtproxy.sh'
```
Скрипт сам напечатает ссылки вида:
```
tg://  tg://proxy?server=<IP>&port=8443&secret=ee<32hex><hex(домен)>
web:   https://t.me/proxy?server=<IP>&port=8443&secret=ee...
```
(хвост после 32 hex = hex-код TLS_DOMAIN, напр. `7777772e676f6f676c652e636f6d` = «www.google.com»)
```
Раздать ссылку — откройте её в Telegram (кнопка «Подключить прокси»).

### Управление
```bash
sudo systemctl status mtproxy          # статус
sudo journalctl -u mtproxy -f          # лог
sudo bash /tmp/mtproxy-links.sh        # показать ссылку снова
sudo bash /tmp/mtproxy-links.sh --regen # сменить секрет (пересоздать config.py) и перезапустить
```

### Настройки (переменные окружения для install-mtproxy.sh)
- `PORT` — порт (TCP+UDP), по умолч. **8443**. Менять → не забыть открыть в Security List.
- `TLS_DOMAIN` — домен для TLS-маскировки (проверяется при старте), по умолч. `www.google.com`.
- `AD_TAG` — рекламный тег от **@MTProxybot** (необязательно).

> Режим `tls` включён по умолчанию: alexbers/mtprotoproxy генерирует секрет с
> префиксом **`ee`** + hex-код TLS-домена — устойчивый к DPI формат (fake-TLS:
> «чужим» клиентам отдаётся настоящий сертификат маскируемого домена).
> Классический `dd`-секрет (без маски) детектятся и режутся — его не используем.

---

## Типичные ошибки и решения

| Симптом | Причина | Лечение |
|---|---|---|
| `HOME: unbound variable` в systemd | системные юниты не получают `HOME` | `: "${HOME:=/root}"` после `set -u` в скрипте + `Environment=HOME=/root` в юните (уже в актуальных файлах) |
| `scp: stat local ... No such file` | команды копирования выполнялись **на сервере** | scp всегда выполнять с домашней машины |
| `Permission denied (publickey)` | невалидный/несовпадающий SSH-ключ (например, два склеенных в поле Oracle) | Serial Console → root/`oracle` → правка `/home/ubuntu/.ssh/authorized_keys` (одна строка .pub) |
| `Out of capacity for A1.Flex` | нет бесплатных ARM-моций в AD | другой AD или E2.1.Micro |
| Нет публичного IP после создания | не проставлен чекбокс | Instance → Instance access → Add public IP (ephemeral) |
| `Connection timed out` к api.telegram.org | региональные блокировки с домашней сети | запускать с сервера (`curl -sI https://api.telegram.org`) |
| @userinfobot не отвечает | написали @userinfobot в чате **своего** бота | бот находится через глобальный поиск Telegram |
| `Bad Request: can't parse entities: Unsupported start tag "br"` | в HTML parse_mode Telegram не поддерживает `<br>` | переводы строк — реальными `\n` в теле (fix от 05.10.2026), экранирование только `&< >` через escape_html |
| `dnf ... Killed` (OOM) при установке на E2.1.Micro | реально ~500 МБ RAM + cgroup-лимит; dnf строит метаданные всех репо → OOM | git не ставить: скрипт берёт исходники tarball'ом (curl); ставит только реально недостающее (curl/python3/cryptography обычно уже есть) |
| Прямой SSH `opc@<прокси>` вешается на banner (TCP 22 открыт) | DPI-срез с домашней сети | входить через jump: `ssh -J ubuntu@<pollerVPS> -i ~/.ssh/proxy-mtproxy opc@<прокси>` |

---

## Журнал действий (05.10.2026)

1. Написан `peer_poller.sh` (полный снимок + diff + события), создан baseline локально.
2. Добавлены Telegram-уведомления (`TG_BOT_TOKEN/TG_CHAT_ID`), `--test-tg`,
   обрезка сообщений длиннее 4096 симв.
3. Созданы `install-server.sh` + `deploy/peer-poller.{service,timer}`.
4. Создан VPS: Oracle Always Free, E2.1.Micro, ca-toronto-1 (AD-1), Ubuntu 24.04.
   A1.Flex в AD-1 был «Out of capacity» → взята E2.1.Micro.
5. Публичный IP добавлен после запуска (в форме не проставился).
6. Файлы скопированы scp → `sudo bash /tmp/install-server.sh` → OK.
7. `.env` заполнен, `--test-tg` OK, baseline создан (5144 проекта, 8 пиров).
8. Ошибка `HOME: unbound variable` в systemd → патчи: `: "${HOME:=/root}"` в скрипте
   + `Environment=HOME=/root` в юните.
9. Добавлены события `PEER_ADDED`/`PEER_REMOVED` (bootstrap новых пиров без NEW-флуда).
10. В peers.txt добавлены `kelvinch`, `noahreyn` (всего 10) — при синке на сервер
    передаются вместе с обновлённым скриптом.

## Журнал действий (MTProto-прокси)

1. Подготовлены `install-mtproxy.sh` + `deploy/mtproxy.service` + `mtproxy-links.sh`
   (официальный `alexbers/mtprotoproxy`, TLS-маскировка, порт 8443 TCP+UDP).
2. (10.10.2026) Инстанс создан как **Oracle Linux 9.8** `instance-20261008-1657`,
   IP **147.5.125.142** (E2.1.Micro). Скрипт: auto-detect ОС (dnf/firewalld/opc).
3. Прямой SSH с домашней вешался на banner (DPI) → доступ через jump (pollerVPS,
   ключ `~/.ssh/peer-poller-vps` + `~/.ssh/proxy-mtproxy`).
4. `dnf` дважды падал по OOM (~500 МБ RAM, cgroup-лимит) при установке git.
   Решено: **git не ставить**, исходники берём tarball'ом через curl
   (curl/python3/cryptography уже были в ОС) → установка прошла без dnf.
5. Прокси запущен (systemd `mtproxy`, active), firewalld открыл 8443 tcp+udp.
   Секрет `ee...`, маска www.google.com. Проверка из pollerVPS: 8443 открыт,
   отдаёт сертификат Google (verify ok) → маскировка и внешний доступ работают.
6. alexbers/mtprotoproxy работает **только по TCP** (UDP в нём нет — проверено по
   коду/README). Значит:
   - в Security List обязателен **8443 TCP** (уже работает — подтверждён извне);
   - **8443 UDP можно не открывать** (прокси его не использует, правило безвредно);
   - осталось: открыть ссылку в Telegram-клиенте на мобильном и убедиться, что
     через прокси заходят в Telegram.
4. IP/порт/домен прокси и ссылка записаны ниже (TODO: вписать после развёртывания).