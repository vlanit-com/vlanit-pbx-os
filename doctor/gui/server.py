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

_cache_lock = threading.Lock()
_cache: dict | None = None
_cache_err: str | None = None


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


def get_report(*, refresh: bool = False) -> tuple[dict | None, str | None]:
    global _cache, _cache_err
    with _cache_lock:
        if refresh or _cache is None:
            _cache, _cache_err = _run_doctor()
        return _cache, _cache_err


def group_stats(checks: list[dict]) -> dict[str, dict[str, int]]:
    out: dict[str, dict[str, int]] = {}
    for c in checks:
        g = c.get("group") or "?"
        st = c.get("status") or "SKIP"
        bucket = out.setdefault(g, {"OK": 0, "FAIL": 0, "SKIP": 0, "total": 0})
        bucket["total"] += 1
        if st in ("OK", "FAIL", "SKIP"):
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


def page_overview(data: dict) -> bytes:
    result = data.get("result", "?")
    host = data.get("host", "")
    checks = data.get("checks") or []
    stats = group_stats(checks)
    fail_n = sum(1 for c in checks if c.get("status") == "FAIL")
    ok_n = sum(1 for c in checks if c.get("status") == "OK")
    skip_n = sum(1 for c in checks if c.get("status") == "SKIP")

    cls = "ok" if result == "OK" else "fail"
    rows = []
    for g, st in stats.items():
        badge = "fail" if st["FAIL"] else ("ok" if st["OK"] else "skip")
        rows.append(
            "<tr>"
            f'<td><a href="/group/{html.escape(g)}">{html.escape(g)}</a></td>'
            f'<td class="st-{badge}">{st["OK"]} OK / {st["FAIL"]} FAIL / {st["SKIP"]} SKIP</td>'
            "</tr>"
        )
    body = f"""
<p class="muted">Хост: {html.escape(str(host))} · read-only · те же проверки, что CLI</p>
<div class="card result-{cls}">
  <h2>Итог: {html.escape(str(result))}</h2>
  <p>{ok_n} OK · {fail_n} FAIL · {skip_n} SKIP</p>
</div>
<table class="data">
  <tr><th>Группа</th><th>Статусы</th></tr>
  {"".join(rows)}
</table>
<p class="actions">
  <a class="btn" href="/?refresh=1">Обновить</a>
  <a class="btn secondary" href="/quit">Выход</a>
</p>
"""
    return render_layout("VLANit doctor", body)


def page_group(data: dict, group: str) -> bytes:
    checks = [c for c in (data.get("checks") or []) if c.get("group") == group]
    rows = []
    for c in checks:
        st = c.get("status") or "SKIP"
        name = html.escape(str(c.get("check") or ""))
        desc = html.escape(str(c.get("desc") or ""))
        hint = html.escape(str(c.get("hint") or ""))
        hint_html = (
            f'<div class="hint">исправить: <code>{hint}</code></div>'
            if st == "FAIL" and hint
            else ""
        )
        rows.append(
            f'<div class="card check-{html.escape(st.lower())}">'
            f'<div><span class="badge st-{html.escape(st.lower())}">{html.escape(st)}</span> '
            f"<strong>{name}</strong></div>"
            f'<p class="muted">{desc}</p>{hint_html}</div>'
        )
    if not rows:
        rows.append('<p class="err">Группа не найдена или пуста.</p>')
    body = f"""
<p><a href="/">← сводка</a></p>
<h2>Группа: {html.escape(group)}</h2>
{"".join(rows)}
<p class="actions">
  <a class="btn secondary" href="/">Сводка</a>
  <a class="btn" href="/?refresh=1">Обновить</a>
</p>
"""
    return render_layout(f"doctor · {group}", body)


def page_error(msg: str) -> bytes:
    body = f'<p class="err">{html.escape(msg)}</p><p class="actions"><a class="btn" href="/?refresh=1">Повторить</a></p>'
    return render_layout("doctor · ошибка", body)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args) -> None:  # quieter
        pass

    def _send(self, code: int, body: bytes, content_type: str = "text/html; charset=utf-8") -> None:
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

        if path.startswith("/static/"):
            rel = path[len("/static/") :]
            if ".." in rel or rel.startswith("/"):
                self._send(400, b"bad path")
                return
            fpath = STATIC / rel
            if not fpath.is_file():
                self._send(404, b"not found")
                return
            ctype = "image/png" if fpath.suffix == ".png" else "text/css; charset=utf-8"
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

        refresh = qs.get("refresh", ["0"])[0] in ("1", "true", "yes")
        data, err = get_report(refresh=refresh)
        if err and data is None:
            self._send(200, page_error(err))
            return
        assert data is not None

        if path == "/" or path == "/index.html":
            self._send(200, page_overview(data))
            return
        if path.startswith("/group/"):
            group = path[len("/group/") :]
            self._send(200, page_group(data, group))
            return
        self._send(404, page_error("Страница не найдена"))


def main() -> None:
    DONE_FILE.parent.mkdir(parents=True, exist_ok=True)
    if DONE_FILE.exists():
        DONE_FILE.unlink()
    # первый прогон в фоне, чтобы / сразу ответил (или refresh подхватит)
    threading.Thread(target=lambda: get_report(refresh=True), daemon=True).start()
    httpd = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"vlanit-doctor-gui: http://127.0.0.1:{PORT}/", flush=True)
    httpd.serve_forever()


if __name__ == "__main__":
    main()
