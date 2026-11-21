#!/usr/bin/env python3
# doctor/gui/server.py — read-only HTML UI для vlanit-doctor (issue #56).
# Без JS; NetSurf-fb. Данные: vlanit-doctor --json.
from __future__ import annotations

import html
import json
import os
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

ROOT = Path(__file__).resolve().parent
STATIC = Path(os.environ.get("VLANIT_DOCTOR_STATIC", str(ROOT / "static")))
TEMPLATES = ROOT / "templates"
PORT = int(os.environ.get("VLANIT_DOCTOR_PORT", "8766"))
DOCTOR_CMD = os.environ.get("VLANIT_DOCTOR_CMD", "vlanit-doctor --json")
DONE_FILE = Path(os.environ.get("VLANIT_DOCTOR_DONE", "/run/vlanit/doctor-gui-done"))
UPDATE_BIN = os.environ.get("VLANIT_UPDATE_BIN", "vlanit-update")
HANDOFF_FLAG = Path(os.environ.get("VLANIT_DOCTOR_HANDOFF", "/run/vlanit/doctor-update-handoff"))

_cache_lock = threading.Lock()
_cache: dict | None = None
_cache_err: str | None = None
_running = False


def _ota_packages() -> list[str]:
    """USB-кандидаты; пустой список → кнопки нет."""
    try:
        out = subprocess.check_output(
            [
                "bash",
                "-c",
                "source /opt/vlanit/lib/checks.sh 2>/dev/null; "
                "command -v ota_list_usb_packages >/dev/null && ota_list_usb_packages",
            ],
            text=True,
            timeout=15,
        )
        return [ln.strip() for ln in out.splitlines() if ln.strip()]
    except Exception:  # noqa: BLE001
        return []


def _handoff_update(pkg: str) -> tuple[str, str]:
    """Popen vlanit-update --gui. Doctor не шлёт YES.
    Returns (status, detail): gui|cli|err."""
    import time

    HANDOFF_FLAG.parent.mkdir(parents=True, exist_ok=True)
    HANDOFF_FLAG.write_text(pkg + "\n", encoding="utf-8")
    env = os.environ.copy()
    env["VLANIT_UPDATE_PKG"] = pkg
    try:
        proc = subprocess.Popen(
            [UPDATE_BIN, "--gui", pkg],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
            start_new_session=True,
        )
        time.sleep(1.2)
        rc = proc.poll()
        if rc is None:
            return "gui", "update GUI запущен"
        err = ""
        try:
            _, err = proc.communicate(timeout=0.2)
        except Exception:  # noqa: BLE001
            pass
        if rc == 2:
            tty = "/dev/tty1" if Path("/dev/tty1").exists() else "/dev/console"
            try:
                with open(tty, "a", encoding="utf-8") as tf:
                    tf.write(
                        f"\nvlanit-doctor: GUI недоступен — CLI: vlanit-update {pkg}\n"
                    )
                subprocess.Popen(
                    [UPDATE_BIN, pkg],
                    stdin=open(tty, "r", encoding="utf-8", errors="ignore"),
                    stdout=open(tty, "w", encoding="utf-8", errors="ignore"),
                    stderr=subprocess.STDOUT,
                    env=env,
                    start_new_session=True,
                )
            except OSError:
                pass
            return "cli", (err or "нет /dev/fb0 / netsurf-fb").strip()
        if rc == 0:
            return "gui", "update GUI завершён"
        return "err", f"vlanit-update --gui exit {rc}: {err}"
    except Exception as exc:  # noqa: BLE001
        return "err", str(exc)


def _run_doctor() -> tuple[dict | None, str | None]:
    try:
        proc = subprocess.run(
            DOCTOR_CMD,
            shell=True,
            check=False,
            capture_output=True,
            text=True,
            timeout=120,
        )
        data = json.loads(proc.stdout)
        if not isinstance(data, dict) or "checks" not in data:
            return None, "некорректный JSON doctor"
        return data, None
    except Exception as exc:  # noqa: BLE001 — UI boundary
        return None, str(exc)


def _bg_run() -> None:
    global _cache, _cache_err, _running
    data, err = _run_doctor()
    with _cache_lock:
        _cache, _cache_err = data, err
        _running = False


def get_report(*, refresh: bool = False) -> tuple[dict | None, str | None, bool]:
    """Returns (data, err, running). running=True → ещё идёт прогон."""
    global _cache, _cache_err, _running
    with _cache_lock:
        if refresh:
            _cache = None
            _cache_err = None
            if not _running:
                _running = True
                threading.Thread(target=_bg_run, daemon=True).start()
            return None, None, True
        if _cache is not None or _cache_err:
            return _cache, _cache_err, False
        if not _running:
            _running = True
            threading.Thread(target=_bg_run, daemon=True).start()
        return None, None, True


def group_stats(checks: list[dict]) -> dict[str, dict[str, int]]:
    out: dict[str, dict[str, int]] = {}
    for c in checks:
        g = c.get("group") or "?"
        st = c.get("status") or "SKIP"
        bucket = out.setdefault(
            g, {"OK": 0, "FAIL": 0, "WARN": 0, "SKIP": 0, "total": 0}
        )
        bucket["total"] += 1
        if st in ("OK", "FAIL", "WARN", "SKIP"):
            bucket[st] += 1
        else:
            bucket["SKIP"] += 1
    return out


def render_layout(title: str, body: str, *, refresh_sec: int | None = None) -> bytes:
    tpl = (TEMPLATES / "layout.html").read_text(encoding="utf-8")
    refresh_meta = (
        f'<meta http-equiv="refresh" content="{refresh_sec}">' if refresh_sec else ""
    )
    logo = ""
    if (STATIC / "logo.png").is_file():
        logo = '<img class="brand" src="/static/logo.png" alt="VLANit">'
    page = (
        tpl.replace("$refresh_meta", refresh_meta)
        .replace("$title_esc", html.escape(title))
        .replace("$brand_css", "")
        .replace("$logo_html", logo)
        .replace("$body", body)
    )
    return page.encode("utf-8")


def page_running() -> bytes:
    body = """
<p class="muted">Идёт проверка (до ~30 с)…</p>
<div class="card"><p>Ждите — страница обновится автоматически.</p></div>
<p class="actions"><a class="btn" href="/">Обновить сейчас</a></p>
"""
    return render_layout("doctor · проверка", body, refresh_sec=2)


def _check_card(c: dict) -> str:
    st = c.get("status") or "SKIP"
    name = html.escape(str(c.get("check") or ""))
    desc = html.escape(str(c.get("desc") or ""))
    hint = html.escape(str(c.get("hint") or ""))
    hint_html = ""
    if hint and st in ("FAIL", "WARN"):
        label = "исправить" if st == "FAIL" else "см."
        hint_html = f'<div class="hint">{label}: <code>{hint}</code></div>'
    return (
        f'<div class="card check-{html.escape(st.lower())}">'
        f'<div><span class="badge st-{html.escape(st.lower())}">{html.escape(st)}</span> '
        f"<strong>{name}</strong></div>"
        f'<p class="muted">{desc}</p>{hint_html}</div>'
    )


def page_overview(data: dict, *, problems_only: bool = False) -> bytes:
    result = data.get("result", "?")
    host = data.get("host", "")
    checks = list(data.get("checks") or [])
    if problems_only:
        checks = [c for c in checks if c.get("status") in ("FAIL", "WARN")]
    stats = group_stats(data.get("checks") or [])
    fail_n = sum(1 for c in (data.get("checks") or []) if c.get("status") == "FAIL")
    warn_n = sum(1 for c in (data.get("checks") or []) if c.get("status") == "WARN")
    ok_n = sum(1 for c in (data.get("checks") or []) if c.get("status") == "OK")
    skip_n = sum(1 for c in (data.get("checks") or []) if c.get("status") == "SKIP")

    cls = {"OK": "ok", "WARN": "warn", "FAIL": "fail"}.get(str(result), "fail")
    rows = []
    for g, st in stats.items():
        if problems_only and st["FAIL"] == 0 and st["WARN"] == 0:
            continue
        badge = (
            "fail"
            if st["FAIL"]
            else ("warn" if st["WARN"] else ("ok" if st["OK"] else "skip"))
        )
        q = "?fail=1" if problems_only else ""
        rows.append(
            "<tr>"
            f'<td><a href="/group/{html.escape(g)}{q}">{html.escape(g)}</a></td>'
            f'<td class="st-{badge}">{st["OK"]} OK / {st["FAIL"]} FAIL / '
            f'{st["WARN"]} WARN / {st["SKIP"]} SKIP</td>'
            "</tr>"
        )

    filter_btn = (
        '<a class="btn secondary" href="/">Все</a>'
        if problems_only
        else '<a class="btn secondary" href="/?fail=1">Только FAIL/WARN</a>'
    )
    detail = ""
    if problems_only:
        cards = [_check_card(c) for c in checks]
        detail = f"<h2>Проблемы</h2>{''.join(cards) if cards else '<p class=\"muted\">Нет FAIL/WARN</p>'}"

    pkgs = _ota_packages()
    update_btn = ""
    if pkgs:
        # один пакет — сразу handoff; несколько — первая страница update GUI
        pkg_q = html.escape(pkgs[0])
        update_btn = (
            f'<a class="btn" href="/action/update?pkg={pkg_q}">Обновить АТС</a>'
            if len(pkgs) == 1
            else '<a class="btn" href="/action/update">Обновить АТС</a>'
        )
        update_btn += (
            f'<span class="muted"> · пакет: {html.escape(Path(pkgs[0]).name)}'
            + (f" (+{len(pkgs)-1})" if len(pkgs) > 1 else "")
            + "</span>"
        )

    body = f"""
<p class="muted">Хост: {html.escape(str(host))} · проверки read-only · OTA через vlanit-update</p>
<div class="card result-{cls}">
  <h2>Итог: {html.escape(str(result))}</h2>
  <p>{ok_n} OK · {fail_n} FAIL · {warn_n} WARN · {skip_n} SKIP</p>
</div>
<table class="data">
  <tr><th>Группа</th><th>Статусы</th></tr>
  {"".join(rows)}
</table>
{detail}
<p class="actions">
  <a class="btn secondary" href="/?refresh=1">Перепроверить</a>
  {filter_btn}
  {update_btn}
  <a class="btn secondary" href="/quit">Выход</a>
</p>
"""
    return render_layout("VLANit doctor", body)


def page_group(data: dict, group: str, *, problems_only: bool = False) -> bytes:
    checks = [c for c in (data.get("checks") or []) if c.get("group") == group]
    if problems_only:
        checks = [c for c in checks if c.get("status") in ("FAIL", "WARN")]
    rows = [_check_card(c) for c in checks]
    if not rows:
        rows.append('<p class="err">Нет пунктов (группа пуста или фильтр).</p>')
    back = "/?fail=1" if problems_only else "/"
    filt = (
        f'<a class="btn secondary" href="/group/{html.escape(group)}">Все в группе</a>'
        if problems_only
        else f'<a class="btn secondary" href="/group/{html.escape(group)}?fail=1">Только FAIL/WARN</a>'
    )
    body = f"""
<p><a href="{back}">← сводка</a></p>
<h2>Группа: {html.escape(group)}</h2>
{"".join(rows)}
<p class="actions">
  <a class="btn secondary" href="{back}">Сводка</a>
  {filt}
  <a class="btn" href="/?refresh=1">Обновить</a>
</p>
"""
    return render_layout(f"doctor · {group}", body)


def page_error(msg: str) -> bytes:
    body = (
        f'<p class="err">{html.escape(msg)}</p>'
        '<p class="actions"><a class="btn" href="/?refresh=1">Повторить</a></p>'
    )
    return render_layout("doctor · ошибка", body)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args) -> None:  # quieter
        pass

    def _send(
        self, code: int, body: bytes, content_type: str = "text/html; charset=utf-8"
    ) -> None:
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        path = parsed.path or "/"
        qs = parse_qs(parsed.query)
        problems = qs.get("fail", ["0"])[0] in ("1", "true", "yes")

        if path.startswith("/static/"):
            rel = path[len("/static/") :]
            if ".." in rel or rel.startswith("/"):
                self._send(400, b"bad path")
                return
            fpath = STATIC / rel
            if not fpath.is_file():
                self._send(404, b"not found")
                return
            ctype = (
                "image/png" if fpath.suffix == ".png" else "text/css; charset=utf-8"
            )
            self._send(200, fpath.read_bytes(), ctype)
            return

        if path == "/quit":
            DONE_FILE.parent.mkdir(parents=True, exist_ok=True)
            DONE_FILE.write_text("ok\n", encoding="utf-8")
            self._send(
                200,
                render_layout(
                    "doctor · выход",
                    '<p class="muted">Можно закрыть. CLI: <code>vlanit-doctor</code></p>',
                ),
            )
            return

        if path == "/action/update":
            pkgs = _ota_packages()
            pkg = (qs.get("pkg") or [""])[0]
            if not pkg:
                pkg = pkgs[0] if pkgs else ""
            if not pkg or not Path(pkg).is_file():
                self._send(
                    200,
                    render_layout(
                        "doctor · update",
                        '<p class="err">Пакет не найден.</p>'
                        '<p class="actions"><a class="btn" href="/">Назад</a></p>',
                    ),
                )
                return
            status, detail = _handoff_update(pkg)
            if status == "gui":
                # освободить FB для update GUI
                DONE_FILE.parent.mkdir(parents=True, exist_ok=True)
                DONE_FILE.write_text("handoff\n", encoding="utf-8")
                body = (
                    f'<p>Запущен <code>vlanit-update --gui</code>.</p>'
                    f'<p class="muted">{html.escape(detail)}</p>'
                    f'<p class="muted">Пакет: <code>{html.escape(pkg)}</code></p>'
                    '<p class="actions"><a class="btn" href="/quit">Закрыть doctor</a></p>'
                )
            elif status == "cli":
                body = (
                    '<p class="err">GUI обновления недоступен — fallback CLI на консоли.</p>'
                    f'<p class="muted">{html.escape(detail)}</p>'
                    f'<p>Выполните при необходимости: '
                    f'<code>vlanit-update {html.escape(pkg)}</code></p>'
                    '<p class="actions"><a class="btn" href="/">Назад</a></p>'
                )
            else:
                body = (
                    f'<p class="err">Handoff: {html.escape(detail)}</p>'
                    f'<p><code>vlanit-update {html.escape(pkg)}</code></p>'
                    '<p class="actions"><a class="btn" href="/">Назад</a></p>'
                )
            self._send(200, render_layout("doctor · update", body))
            return

        refresh = qs.get("refresh", ["0"])[0] in ("1", "true", "yes")
        data, err, running = get_report(refresh=refresh)
        if running and data is None and err is None:
            self._send(200, page_running())
            return
        if err and data is None:
            self._send(200, page_error(err))
            return
        assert data is not None

        if path == "/" or path == "/index.html":
            self._send(200, page_overview(data, problems_only=problems))
            return
        if path.startswith("/group/"):
            group = path[len("/group/") :]
            self._send(200, page_group(data, group, problems_only=problems))
            return
        self._send(404, page_error("Страница не найдена"))


def main() -> None:
    DONE_FILE.parent.mkdir(parents=True, exist_ok=True)
    if DONE_FILE.exists():
        DONE_FILE.unlink()
    threading.Thread(target=lambda: get_report(refresh=True), daemon=True).start()
    httpd = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"vlanit-doctor-gui: http://127.0.0.1:{PORT}/", flush=True)
    httpd.serve_forever()


if __name__ == "__main__":
    main()
