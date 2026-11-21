#!/usr/bin/env python3
# update/gui/server.py — HTML UI для vlanit-update (issue #58).
# Apply: VLANIT_ASSUME_YES=1 vlanit-update <pkg>. Confirm YES только здесь.
from __future__ import annotations

import html
import os
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

ROOT = Path(__file__).resolve().parent
STATIC = Path(os.environ.get("VLANIT_UPDATE_STATIC", str(ROOT / "static")))
PORT = int(os.environ.get("VLANIT_UPDATE_PORT", "8767"))
DONE_FILE = Path(os.environ.get("VLANIT_UPDATE_DONE", "/run/vlanit/update-gui-done"))
UPDATE_BIN = os.environ.get("VLANIT_UPDATE_BIN", "vlanit-update")
STATE_DIR = Path(os.environ.get("VLANIT_UPDATE_STATE", "/run/vlanit/update-gui"))

_lock = threading.Lock()
_apply_proc: subprocess.Popen | None = None
_apply_rc: int | None = None
_apply_log: str = ""


def render(title: str, body: str) -> bytes:
    css = "/static/style.css"
    doc = f"""<!DOCTYPE html>
<html lang="ru"><head>
<meta charset="utf-8">
<meta http-equiv="refresh" content="3">
<title>{html.escape(title)}</title>
<link rel="stylesheet" href="{css}">
</head><body>
<h1>VLANit обновление АТС</h1>
{body}
</body></html>
"""
    return doc.encode("utf-8")


def list_usb_packages() -> list[str]:
    override = os.environ.get("VLANIT_OTA_PACKAGES", "").strip()
    if override:
        return [p for p in override.split(":") if p and Path(p).is_file()]
    env_pkg = os.environ.get("VLANIT_UPDATE_PKG", "").strip()
    if env_pkg and Path(env_pkg).is_file():
        return [env_pkg]
    try:
        out = subprocess.check_output(
            [
                "bash",
                "-c",
                'source /opt/vlanit/lib/checks.sh 2>/dev/null || source "'
                + str(ROOT.parents[1] / "rootfs/lib-checks.sh")
                + '"; ota_list_usb_packages',
            ],
            text=True,
            timeout=15,
        )
        return [ln.strip() for ln in out.splitlines() if ln.strip()]
    except Exception:  # noqa: BLE001
        return []


def page_pick(pkgs: list[str]) -> bytes:
    if not pkgs:
        body = """
<p class="err">Пакет не найден. Подключите USB с <code>vlanit-update-*.tar</code> + <code>.asc</code>.</p>
<p class="actions">
  <a class="btn" href="/">Повторить</a>
  <a class="btn secondary" href="/quit">Выход</a>
</p>
<p class="muted">CLI: <code>vlanit-update</code></p>
"""
        return render("update · нет пакета", body)
    items = []
    for p in pkgs:
        items.append(
            f'<li class="card"><a class="btn" href="/confirm?pkg={html.escape(p)}">'
            f"{html.escape(Path(p).name)}</a>"
            f'<div class="muted">{html.escape(p)}</div></li>'
        )
    body = f"""
<p class="muted">Выберите пакет обновления (GPG-подпись обязательна).</p>
<ul class="pkgs">{"".join(items)}</ul>
<p class="actions"><a class="btn secondary" href="/quit">Выход</a></p>
"""
    return render("update · пакет", body)


def page_confirm(pkg: str) -> bytes:
    size = "?"
    try:
        size = f"{Path(pkg).stat().st_size // (1024 * 1024)} MiB"
    except OSError:
        pass
    body = f"""
<div class="card">
  <h2>Сводка</h2>
  <p>Пакет: <code>{html.escape(pkg)}</code></p>
  <p>Объём: {html.escape(size)}</p>
  <p>Будет создан снапшот <code>pre-update</code>, затем импорт образа АТС.</p>
  <p class="muted">Откат: <code>vlanit-rollback</code></p>
</div>
<p class="actions">
  <a class="btn danger" href="/apply?pkg={html.escape(pkg)}&yes=1">YES — применить</a>
  <a class="btn secondary" href="/">Отмена</a>
</p>
"""
    return render("update · confirm", body)


def page_apply(pkg: str) -> bytes:
    global _apply_proc, _apply_rc, _apply_log
    with _lock:
        if _apply_proc is None and _apply_rc is None:
            STATE_DIR.mkdir(parents=True, exist_ok=True)
            logf = STATE_DIR / "apply.log"

            def _run() -> None:
                global _apply_proc, _apply_rc, _apply_log
                env = os.environ.copy()
                env["VLANIT_ASSUME_YES"] = "1"
                with open(logf, "w", encoding="utf-8") as fh:
                    proc = subprocess.Popen(
                        [UPDATE_BIN, pkg],
                        stdout=fh,
                        stderr=subprocess.STDOUT,
                        env=env,
                        stdin=subprocess.DEVNULL,
                    )
                    with _lock:
                        _apply_proc = proc
                    rc = proc.wait()
                    with _lock:
                        _apply_rc = rc
                        _apply_proc = None
                        try:
                            _apply_log = logf.read_text(encoding="utf-8", errors="replace")[-4000:]
                        except OSError:
                            _apply_log = ""

            threading.Thread(target=_run, daemon=True).start()
            body = f"""
<p class="progress">Запуск обновления…</p>
<p class="muted">{html.escape(pkg)}</p>
<p class="actions"><a class="btn" href="/status">Статус</a></p>
"""
            return render("update · apply", body)

    return page_status()


def page_status() -> bytes:
    with _lock:
        rc = _apply_rc
        running = _apply_proc is not None
        log_tail = _apply_log
    if running or rc is None:
        # подтянуть лог с диска
        logf = STATE_DIR / "apply.log"
        try:
            log_tail = logf.read_text(encoding="utf-8", errors="replace")[-4000:]
        except OSError:
            pass
        body = f"""
<p class="progress">Идёт обновление (снапшот → import → restart → health)…</p>
<pre class="card muted">{html.escape(log_tail or "…")}</pre>
<p class="actions"><a class="btn" href="/status">Обновить статус</a></p>
"""
        return render("update · progress", body)
    if rc == 0:
        body = f"""
<div class="card"><h2>OK</h2>
<p>Обновление АТС завершено.</p>
<p class="muted">Откат: <code>vlanit-rollback</code></p></div>
<pre class="card muted">{html.escape(log_tail[-1500:])}</pre>
<p class="actions"><a class="btn" href="/quit">Выход</a></p>
"""
        return render("update · OK", body)
    body = f"""
<div class="card"><h2 class="err">Ошибка (код {rc})</h2>
<p>См. лог. CLI: <code>tail /var/log/vlanit-update.log</code></p></div>
<pre class="card muted">{html.escape(log_tail[-2000:])}</pre>
<p class="actions">
  <a class="btn" href="/">Сначала</a>
  <a class="btn secondary" href="/quit">Выход</a>
</p>
"""
    return render("update · FAIL", body)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args) -> None:
        pass

    def _send(self, code: int, body: bytes, ctype: str = "text/html; charset=utf-8") -> None:
        self.send_response(code)
        self.send_header("Content-Type", ctype)
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
                self._send(400, b"bad")
                return
            fpath = STATIC / rel
            if not fpath.is_file():
                self._send(404, b"missing")
                return
            self._send(200, fpath.read_bytes(), "text/css; charset=utf-8")
            return

        if path == "/quit":
            DONE_FILE.parent.mkdir(parents=True, exist_ok=True)
            DONE_FILE.write_text("ok\n", encoding="utf-8")
            self._send(
                200,
                render(
                    "update · выход",
                    '<p class="muted">Можно закрыть. CLI: <code>vlanit-update</code></p>',
                ),
            )
            return

        if path == "/confirm":
            pkg = (qs.get("pkg") or [""])[0]
            if not pkg or not Path(pkg).is_file():
                self._send(200, page_pick(list_usb_packages()))
                return
            self._send(200, page_confirm(pkg))
            return

        if path == "/apply":
            pkg = (qs.get("pkg") or [""])[0]
            yes = (qs.get("yes") or [""])[0]
            if yes != "1" or not pkg or not Path(pkg).is_file():
                self._send(200, page_pick(list_usb_packages()))
                return
            self._send(200, page_apply(pkg))
            return

        if path == "/status":
            self._send(200, page_status())
            return

        if path in ("/", "/index.html"):
            self._send(200, page_pick(list_usb_packages()))
            return
        self._send(404, render("404", '<p class="err">Не найдено</p>'))


def main() -> None:
    DONE_FILE.parent.mkdir(parents=True, exist_ok=True)
    if DONE_FILE.exists():
        DONE_FILE.unlink()
    httpd = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"vlanit-update-gui: http://127.0.0.1:{PORT}/", flush=True)
    httpd.serve_forever()


if __name__ == "__main__":
    main()
