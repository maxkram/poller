#!/usr/bin/env python3
"""
peers_web.py — мини-web UI для управления списком пиров (peer-poller).

Только стандартная библиотека. Запускается системным юнитом peer-poller-web.service.

Доступ:  http://<IP>:8080/p/<токен из web_token>
Действия: список пиров со статистикой из state, добавление, удаление,
           ручной опрос, последние события. Изменения списка автоматически
           запускают цикл peer_poller.sh --once (если не снять чекбокс).
"""
import datetime
import html
import http.server
import os
import re
import secrets
import subprocess
import threading
from urllib.parse import parse_qs

BASE = os.environ.get("PEER_POLLER_HOME", "/opt/peer-poller")
PEERS_FILE = os.path.join(BASE, "peers.txt")
STATE_FILE = os.path.join(BASE, "state", "peers_state.tsv")
HISTORY_FILE = os.path.join(BASE, "state", "peers_history.log")
POLLER = os.path.join(BASE, "peer_poller.sh")
TOKEN_FILE = os.path.join(BASE, "web_token")
PORT = int(os.environ.get("WEB_PORT", "8080"))
POLL_TIMEOUT = 240

VALID_LOGIN = re.compile(r"^[A-Za-z0-9._-]{1,32}$")
LOCK = threading.Lock()
ACTIVE = ("IN_PROGRESS", "IN_REVIEWS", "ACCEPTED")


def now_iso():
    return datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def get_token():
    try:
        with open(TOKEN_FILE) as f:
            t = f.read().strip()
            if t:
                return t
    except FileNotFoundError:
        pass
    t = secrets.token_urlsafe(16)
    with open(TOKEN_FILE, "w") as f:
        f.write(t + "\n")
    os.chmod(TOKEN_FILE, 0o600)
    return t


def read_peers():
    peers = []
    if os.path.exists(PEERS_FILE):
        with open(PEERS_FILE) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                peers.append(line)
    return peers


def write_peers(peers):
    tmp = PEERS_FILE + ".tmp"
    with open(tmp, "w") as f:
        f.write("# Список пиров, отслеживаемых peer-poller\n")
        for p in peers:
            f.write(p + "\n")
        f.write("\n")
    os.replace(tmp, PEERS_FILE)


def snapshot_stats():
    """login -> dict(total, active, in_progress, in_reviews, accepted, last)"""
    stats = {}
    if not os.path.exists(STATE_FILE):
        return stats
    with open(STATE_FILE) as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 5:
                continue
            login, status, last = parts[0], parts[2], parts[4]
            s = stats.setdefault(login, {"total": 0, "active": 0, "ip": 0,
                                         "ir": 0, "acc": 0, "last": ""})
            s["total"] += 1
            if status in ACTIVE:
                s["active"] += 1
            if status == "IN_PROGRESS":
                s["ip"] += 1
            elif status == "IN_REVIEWS":
                s["ir"] += 1
            elif status == "ACCEPTED":
                s["acc"] += 1
            if last > s["last"]:
                s["last"] = last
    return stats


def last_events(n=12):
    if not os.path.exists(HISTORY_FILE):
        return []
    with open(HISTORY_FILE) as f:
        lines = f.readlines()
    return [l.rstrip("\n") for l in lines[-n:]]


def run_poll():
    """Запускает peer_poller.sh --once; возвращает (rc, tail вывода)."""
    try:
        with LOCK:
            r = subprocess.run(["bash", POLLER, "--once"],
                               capture_output=True, text=True, timeout=POLL_TIMEOUT)
    except subprocess.TimeoutExpired:
        return 1, "опрос не завершился за %d с" % POLL_TIMEOUT
    tail = (r.stdout + r.stderr).strip().splitlines()
    tail = "\n".join(tail[-12:])
    return r.returncode, tail


PAGE = """<!doctype html>
<html lang="ru"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>peer-poller — управление пирами</title>
<style>
  body{font-family:system-ui,sans-serif;margin:2rem auto;max-width:860px;padding:0 1rem;color:#222}
  h1{font-size:1.4rem}
  table{border-collapse:collapse;width:100%;margin:.6rem 0 1.2rem}
  th,td{border:1px solid #ddd;padding:.45rem .6rem;text-align:left;font-size:.92rem}
  th{background:#f5f5f5}
  .box{background:#fafafa;border:1px solid #e3e3e3;border-radius:8px;padding:1rem;margin:1rem 0}
  .btn{border:0;border-radius:6px;padding:.5rem .9rem;font-size:.95rem;cursor:pointer}
  .add{background:#2563eb;color:#fff}.rem{background:#dc2626;color:#fff}
  .poll{background:#059669;color:#fff}.btn:disabled{opacity:.5;cursor:default}
  input[type=text]{padding:.45rem .6rem;border:1px solid #ccc;border-radius:6px;width:320px;max-width:60%}
  .status{background:#fff;border-left:4px solid #2563eb;padding:.6rem .8rem;margin:.6rem 0;
          white-space:pre-wrap;font-size:.9rem;border-radius:0 6px 6px 0}
  .warn{border-left-color:#dc2626}.ok{border-left-color:#059669}
  .hist{font-size:.85rem;color:#555;white-space:pre-wrap}
  .meta{color:#888;font-size:.85rem}
</style></head><body>
<h1>📡 peer-poller — список пиров <span class="meta">(опрос каждые ~10 мин)</span></h1>

<form method="post" action="/p/__TOKEN__" onsubmit="return pre()">
<div class="box">
  <b>Добавить пиров</b> <span class="meta">(логин или список через запятую/пробел)</span><br><br>
  <input type="text" name="names" placeholder="например: kelvinch, noahreyn">
  <label style="margin-left:.8rem"><input type="checkbox" name="poll" value="1" checked>
    запустить опрос сразу после изменения</label>
  <button class="btn add" type="submit" name="action" value="add">＋ Добавить</button>
  <button class="btn poll" type="submit" name="action" value="pollnow">▶ Опросить сейчас</button>
</div>
</form>

<form method="post" action="/p/__TOKEN__">
<div class="box">
<table>
<tr><th></th><th>Логин</th><th>Всего проектов</th><th>Активных (IP/IR/A)</th><th>Обновлено</th></tr>
__ROWS__
</table>
<label><input type="checkbox" name="poll" value="1" checked> запустить опрос после удаления</label>
<button class="btn rem" type="submit" name="action" value="remove">－ Удалить выбранных</button>
</div>
</form>

<div class="box">
<b>Последние события</b>
<div class="hist">__HIST__</div>
</div>
<script>
function pre(){if(!confirm('Точно изменить список пиров?'))return false;return true}
</script>
</body></html>
"""

CSSJS = ""  # (стили уже в PAGE)


def build_rows():
    peers = read_peers()
    stats = snapshot_stats()
    if not peers:
        return "<tr><td colspan=5>— список пуст, добавьте пиров —</td></tr>"
    rows = []
    for p in peers:
        s = stats.get(p, {})
        rows.append(
            "<tr><td><input type='checkbox' name='sel' value='%s'></td>"
            "<td><b>%s</b></td><td>%s</td><td>%s</td><td class='meta'>%s</td></tr>"
            % (html.escape(p), html.escape(p),
               s.get("total", "— (нет в снимке)"),
               "%d (%d/%d/%d)" % (s.get("active", 0), s.get("ip", 0),
                                  s.get("ir", 0), s.get("acc", 0)),
               html.escape(s.get("last", ""))))
    return "\n".join(rows)


def build_page(message="", mclass=""):
    hist = "\n".join(html.escape(l) for l in last_events()) or "(пока пусто)"
    page = (PAGE.replace("__TOKEN__", get_token())
                 .replace("__ROWS__", build_rows())
                 .replace("__HIST__", hist))
    if message:
        page = page.replace("<h1>",
                            '<div class="status %s">%s</div><h1>'
                            % (mclass, html.escape(message)))
    return page.encode("utf-8")


def parse_names(raw):
    return [x for x in re.split(r"[,\s]+", raw.strip()) if x]


class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "peer-poller-web/1.0"

    def _send(self, code, body):
        self.send_response(code)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):  # тише: только в stderr journald
        pass

    def do_GET(self):
        if self.path == "/p/" + get_token():
            self._send(200, build_page())
        else:
            self._send(404, b"not found")

    def do_POST(self):
        if self.path != "/p/" + get_token():
            self._send(404, b"not found")
            return
        length = int(self.headers.get("Content-Length", 0))
        form = self.rfile.read(length).decode("utf-8")
        params = parse_qs(form)  # decode application/x-www-form-urlencoded
        action = (params.get("action") or [""])[0]
        want_poll = "1" in params.get("poll", [])
        message, mclass = "", ""

        if action == "add":
            names = parse_names((params.get("names") or [""])[0])
            bad = [n for n in names if not VALID_LOGIN.match(n)]
            if bad:
                message = "Невалидные логины (пропуск): %s" % ", ".join(bad)
                mclass = "warn"
            current = read_peers()
            fresh = [n for n in names if n not in current and VALID_LOGIN.match(n)]
            if not fresh:
                message = (message + "\n" if message else "") + "Новых пиров нет (уже есть или невалидные)"
                mclass = mclass or "warn"
            else:
                write_peers(current + fresh)
                message = ("Добавлены: %s" % ", ".join(fresh))
                mclass = "ok"
                if bad:
                    message += "\nПропущены (невалидные): %s" % ", ".join(bad)
        elif action == "remove":
            sel = [s for s in params.get("sel", []) if s]
            current = read_peers()
            left = [p for p in current if p not in sel]
            if not left:
                message = "Нельзя удалить всех пиров — список станет пустым"
                mclass = "warn"
            else:
                removed = [p for p in current if p not in left]
                write_peers(left)
                message = "Удалены: %s" % ", ".join(removed)
                mclass = "ok"
        elif action == "pollnow":
            pass
        else:
            self._send(400, b"bad request")
            return

        if want_poll and action in ("add", "remove", "pollnow"):
            rc, tail = run_poll()
            prefix = "Опрос: OK" if rc == 0 else "Опрос: ОШИБОКА (rc=%d)" % rc
            message = (message + "\n\n" if message else "") + prefix + "\n" + tail
            mclass = "ok" if rc == 0 else "warn"
        elif action in ("add", "remove"):
            message = (message + "\n" if message else "") + \
                "Опрос не запускался — список обновится в ближайший цикл (~10 мин)"

        self._send(200, build_page(message, mclass))


def main():
    bind = os.environ.get("WEB_BIND", "0.0.0.0")
    srv = http.server.ThreadingHTTPServer((bind, PORT), Handler)
    print("peer-poller web UI: http://%s:%d/p/%s" % (bind, PORT, get_token()), flush=True)
    srv.serve_forever()


if __name__ == "__main__":
    main()