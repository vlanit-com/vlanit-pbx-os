#!/usr/bin/env python3
"""VLANit installer HTML UI (NetSurf-fb, без JS).

Слушает 127.0.0.1:8765. Собирает config → /run/vlanit/install-config.json,
пишет /run/vlanit/gui-done и выходит (bash запускает stages).

Экраны: installer/screens.yaml (порядок + enabled).
Брендинг: installer/branding/<VLANIT_BRANDING>/ (default).
"""
from __future__ import annotations

import html
import json
import os
import subprocess
import sys
import threading
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from string import Template

try:
    import yaml  # type: ignore
except ImportError:  # pragma: no cover
    yaml = None  # noqa: N816

HOST = "127.0.0.1"
PORT = int(os.environ.get("VLANIT_GUI_PORT", "8765"))
INSTALLER_DIR = Path(os.environ.get("INSTALLER_DIR", "/opt/vlanit/installer"))
STATIC = Path(os.environ.get("VLANIT_GUI_STATIC", str(INSTALLER_DIR / "gui" / "static")))
TEMPLATES = INSTALLER_DIR / "gui" / "templates"
SCREENS_FILE = INSTALLER_DIR / "screens.yaml"
BRAND_NAME = os.environ.get("VLANIT_BRANDING", "default")
BRAND_DIR = INSTALLER_DIR / "branding" / BRAND_NAME
PROBE = INSTALLER_DIR / "bin" / "vlanit-probe"
RUN_DIR = Path("/run/vlanit")
CONFIG_PATH = RUN_DIR / "install-config.json"
DONE_FLAG = RUN_DIR / "gui-done"
PROGRESS_PATH = RUN_DIR / "progress.json"
FINISH_PATH = RUN_DIR / "finish.txt"
MODE = os.environ.get("VLANIT_GUI_MODE", "collect")  # collect | progress | finish

# --- registry + branding ---


def _load_yaml(path: Path) -> dict | list:
    text = path.read_text(encoding="utf-8")
    if yaml is not None:
        return yaml.safe_load(text) or {}
    # минимальный fallback без PyYAML (только наш простой screens/branding)
    raise RuntimeError(f"нужен python3-yaml для чтения {path}")


def load_screens() -> list[dict]:
    data = _load_yaml(SCREENS_FILE)
    return list(data.get("screens") or [])


def load_branding() -> dict:
    cfg_path = BRAND_DIR / "branding.yaml"
    if not cfg_path.is_file():
        return {
            "product_name": "VLANit PBX OS",
            "logo": "logo.png",
            "colors": {},
        }
    return dict(_load_yaml(cfg_path) or {})


SCREENS = load_screens()
BRAND = load_branding()


def screens_phase(phase: str) -> list[dict]:
    return [s for s in SCREENS if s.get("enabled", True) and s.get("phase") == phase]


def collect_screens() -> list[dict]:
    return screens_phase("collect")


def first_collect_id() -> str:
    cs = collect_screens()
    return cs[0]["id"] if cs else "hardware"


def screen_meta(sid: str) -> dict | None:
    for s in SCREENS:
        if s.get("id") == sid:
            return s
    return None


def screen_title(sid: str) -> str:
    for i, s in enumerate(collect_screens()):
        if s["id"] == sid:
            return f"Экран {i + 1}. {s.get('title', sid)}"
    meta = screen_meta(sid)
    if meta:
        # progress/finish — номер после всех collect
        n = len(collect_screens()) + 1
        if meta.get("phase") == "finish":
            n += 1
        return f"Экран {n}. {meta.get('title', sid)}"
    return sid


def next_collect_id(sid: str) -> str | None:
    ids = [s["id"] for s in collect_screens()]
    if sid not in ids:
        return ids[0] if ids else None
    i = ids.index(sid)
    return ids[i + 1] if i + 1 < len(ids) else None


def prev_collect_id(sid: str) -> str | None:
    ids = [s["id"] for s in collect_screens()]
    if sid not in ids:
        return None
    i = ids.index(sid)
    return ids[i - 1] if i > 0 else None


def brand_css() -> str:
    colors = BRAND.get("colors") or {}
    mapping = {
        "bg": "--vlanit-bg",
        "card": "--vlanit-card",
        "text": "--vlanit-text",
        "muted": "--vlanit-muted",
        "accent": "--vlanit-accent",
        "border": "--vlanit-border",
        "input_bg": "--vlanit-input-bg",
        "input_border": "--vlanit-input-border",
        "button_text": "--vlanit-button-text",
        "error_bg": "--vlanit-error-bg",
        "error_border": "--vlanit-error-border",
        "error_text": "--vlanit-error-text",
    }
    lines = [":root {"]
    for key, var in mapping.items():
        if key in colors and colors[key]:
            lines.append(f"  {var}: {colors[key]};")
    lines.append("}")
    theme = BRAND_DIR / "theme.css"
    extra = theme.read_text(encoding="utf-8") if theme.is_file() else ""
    return "\n".join(lines) + "\n" + extra


def brand_logo_html() -> str:
    logo = BRAND.get("logo") or "logo.png"
    path = BRAND_DIR / logo
    if path.is_file():
        return f'<img class="brand" src="/branding/{html.escape(logo)}" alt="{esc(BRAND.get("product_name", "VLANit"))}">'
    # fallback static
    for name in ("logo.png", "logo.svg"):
        if (STATIC / name).exists():
            return f'<img class="brand" src="/static/{name}" alt="VLANit">'
    return ""


state: dict = {
    "screen": first_collect_id(),
    "error": "",
    "disk": "",
    "mirror_mode": "single",
    "mirror_disk": "",
    "iface": "",
    "net_mode": "dhcp",
    "net_addr": "",
    "net_gw": "",
    "net_dns": "9.9.9.9",
    "hostname": "vlanit-pbx",
    "admin_user": "vlanit",
    "admin_pass": "",
    "ssh": "yes",
    "timezone": "Europe/Moscow",
    "wg": "no",
    "wg_addr": "10.66.66.1/24",
    "wg_port": "51820",
    "pbx_name": "VLANit-PBX",
    "pbx_pass": "",
}


def form_row(label: str, control: str) -> str:
    return (
        f'<tr><td class="lbl">{esc(label)}</td>'
        f'<td class="ctl">{control}</td></tr>'
    )


def probe(kind: str) -> dict:
    out = subprocess.check_output([str(PROBE), kind], text=True)
    return json.loads(out)


def esc(s: object) -> str:
    return html.escape("" if s is None else str(s))


def page(title: str, body: str, refresh: int | None = None) -> bytes:
    meta = f'<meta http-equiv="refresh" content="{refresh}">' if refresh else ""
    layout_path = TEMPLATES / "layout.html"
    if layout_path.is_file():
        tpl = Template(layout_path.read_text(encoding="utf-8"))
        doc = tpl.safe_substitute(
            refresh_meta=meta,
            title_esc=esc(title),
            brand_css=brand_css(),
            logo_html=brand_logo_html(),
            body=body,
        )
    else:
        doc = f"""<!DOCTYPE html><html lang="ru"><head><meta charset="utf-8">{meta}
<title>{esc(title)}</title><link rel="stylesheet" href="/static/style.css"></head>
<body><div class="wrap">{brand_logo_html()}<h1>{esc(title)}</h1>{body}</div></body></html>"""
    return doc.encode("utf-8")


def err_box() -> str:
    if not state.get("error"):
        return ""
    return f'<div class="err">{esc(state["error"])}</div>'


def hidden_screen(sid: str) -> str:
    return f'<input type="hidden" name="screen" value="{esc(sid)}">'


def nav_buttons(show_back: bool = True) -> str:
    back = (
        '<button class="secondary" type="submit" name="action" value="back">Назад</button>\n'
        if show_back
        else ""
    )
    return f'<div class="actions">\n{back}<button type="submit" name="action" value="next">Далее</button>\n</div>'


# --- render handlers (id → callable) ---


def render_hardware() -> bytes:
    hw = probe("hardware")
    warn = hw.get("warnings") or ""
    body = err_box() + f"""
<div class="card">
<p>Процессор: {esc(hw.get("cpu"))} ({esc(hw.get("cores"))} ядер)</p>
<p>ОЗУ: {esc(hw.get("ram_mb"))} МБ</p>
<p>Интерфейсы: {esc(" ".join(hw.get("interfaces") or []))}</p>
<p>Режим загрузки: {esc(hw.get("boot_mode"))}</p>
{"<p class='warn'>ПРЕДУПРЕЖДЕНИЯ: " + esc(warn) + "</p>" if warn else ""}
</div>
<form method="post" action="/">
{hidden_screen("hardware")}
<div class="actions"><button type="submit" name="action" value="next">Далее</button></div>
</form>
"""
    return page(screen_title("hardware"), body)


def render_disk() -> bytes:
    data = probe("disks")
    disks = data.get("disks") or []
    options = []
    for d in disks:
        sel = " selected" if d["dev"] == state.get("disk") else ""
        label = f'{d["dev"]}  {d["size_gib"]} GiB  {d.get("model","")}  [{d.get("tran","")}]'
        options.append(f'<option value="{esc(d["dev"])}"{sel}>{esc(label)}</option>')
    mirror_opts = '<option value="">— нет —</option>'
    for d in disks:
        if d["dev"] == state.get("disk"):
            continue
        sel = " selected" if d["dev"] == state.get("mirror_disk") else ""
        mirror_opts += f'<option value="{esc(d["dev"])}"{sel}>{esc(d["dev"])} ({d["size_gib"]} GiB)</option>'

    def _img(base: str, alt: str) -> str:
        for ext in ("png", "svg"):
            if (STATIC / f"{base}.{ext}").exists():
                return f'<img class="disk-scheme" src="/static/{base}.{ext}" alt="{alt}">'
        return ""

    scheme = _img("disk-scheme", "схема диска")
    mirror_img = _img("mirror-scheme", "зеркало") if len(disks) >= 2 else ""
    body = err_box() + f"""
{scheme}
{mirror_img}
<form method="post" action="/">
{hidden_screen("disk")}
<table class="form">
{form_row("Целевой диск", f'<select name="disk">{"".join(options) or "<option value=\'\'>нет дисков</option>"}</select>')}
{form_row("Режим", '''<select name="mirror_mode">
<option value="single"''' + (" selected" if state.get("mirror_mode") != "raid1" else "") + '''>Один диск</option>
<option value="raid1"''' + (" selected" if state.get("mirror_mode") == "raid1" else "") + '''>Зеркало RAID1</option>
</select>''')}
{form_row("Второй диск", f'<select name="mirror_disk">{mirror_opts}</select>')}
</table>
<p class="muted">Целевой диск будет полностью очищен. Второй диск — только для режима RAID1.</p>
{nav_buttons()}
</form>
"""
    return page(screen_title("disk"), body)


def render_network() -> bytes:
    data = probe("ifaces")
    ifaces = data.get("interfaces") or []
    opts = []
    for i in ifaces:
        sel = " selected" if i["name"] == state.get("iface") else ""
        opts.append(
            f'<option value="{esc(i["name"])}"{sel}>{esc(i["name"])} ({esc(i.get("mac",""))})</option>'
        )
    body = err_box() + f"""
<form method="post" action="/">
{hidden_screen("network")}
<table class="form">
{form_row("Интерфейс", f'<select name="iface">{"".join(opts)}</select>')}
{form_row("Режим", '''<select name="net_mode">
<option value="dhcp"''' + (" selected" if state.get("net_mode") != "static" else "") + '''>DHCP</option>
<option value="static"''' + (" selected" if state.get("net_mode") == "static" else "") + '''>Статический IPv4</option>
</select>''')}
{form_row("Адрес (CIDR)", f'<input type="text" name="net_addr" value="{esc(state.get("net_addr"))}">')}
{form_row("Шлюз", f'<input type="text" name="net_gw" value="{esc(state.get("net_gw"))}">')}
{form_row("DNS", f'<input type="text" name="net_dns" value="{esc(state.get("net_dns") or "9.9.9.9")}">')}
</table>
{nav_buttons()}
</form>
"""
    return page(screen_title("network"), body)


def render_system() -> bytes:
    body = err_box() + f"""
<form method="post" action="/">
{hidden_screen("system")}
<div class="card">
<table class="form">
{form_row("Hostname", f'<input type="text" name="hostname" value="{esc(state.get("hostname"))}">')}
{form_row("Администратор", f'<input type="text" name="admin_user" value="{esc(state.get("admin_user"))}">')}
{form_row("Пароль (мин. 8)", '<input type="password" name="admin_pass" value="">')}
{form_row("SSH", '''<select name="ssh">
<option value="yes"''' + (" selected" if state.get("ssh") != "no" else "") + '''>Включить</option>
<option value="no"''' + (" selected" if state.get("ssh") == "no" else "") + '''>Отключить</option>
</select>''')}
{form_row("Часовой пояс", f'<input type="text" name="timezone" value="{esc(state.get("timezone"))}">')}
{form_row("Имя АТС", f'<input type="text" name="pbx_name" value="{esc(state.get("pbx_name"))}">')}
{form_row("Пароль веб-АТС", '<input type="password" name="pbx_pass" value="" placeholder="пусто = автоген">')}
</table>
<p class="muted">Часовой пояс — IANA (напр. Europe/Moscow). Пустой пароль веб-АТС = автоген.</p>
</div>
{nav_buttons()}
</form>
"""
    return page(screen_title("system"), body)


def render_wireguard() -> bytes:
    body = err_box() + f"""
<form method="post" action="/">
{hidden_screen("wireguard")}
<div class="card">
<table class="form">
{form_row("WireGuard", '''<select name="wg">
<option value="no"''' + (" selected" if state.get("wg") != "yes" else "") + '''>Не включать</option>
<option value="yes"''' + (" selected" if state.get("wg") == "yes" else "") + '''>Включить после установки</option>
</select>''')}
{form_row("Адрес wg0", f'<input type="text" name="wg_addr" value="{esc(state.get("wg_addr") or "10.66.66.1/24")}">')}
{form_row("Порт", f'<input type="text" name="wg_port" value="{esc(state.get("wg_port") or "51820")}">')}
</table>
<p class="muted">При «Не включать» адрес и порт не применяются. Ключи генерируются при установке.</p>
</div>
{nav_buttons()}
</form>
"""
    return page(screen_title("wireguard"), body)


def render_confirm() -> bytes:
    mirror = ""
    if state.get("mirror_mode") == "raid1" and state.get("mirror_disk"):
        mirror = f"Зеркало: RAID1 ({state['disk']} + {state['mirror_disk']})"
    wg_line = "выкл"
    if state.get("wg") == "yes":
        wg_line = f"вкл ({state.get('wg_addr')}, порт {state.get('wg_port')})"
    body = err_box() + f"""
<div class="card">
<pre style="white-space:pre-wrap;font-family:inherit">Целевой диск: {esc(state.get("disk"))}
{esc(mirror)}
Сеть: {esc(state.get("net_mode"))} ({esc(state.get("iface"))})
Hostname: {esc(state.get("hostname"))}
Часовой пояс: {esc(state.get("timezone"))}
Админ: {esc(state.get("admin_user"))}
SSH: {esc(state.get("ssh"))}
Имя АТС: {esc(state.get("pbx_name"))}
WireGuard: {esc(wg_line)}

ВСЕ ДАННЫЕ НА ДИСКЕ БУДУТ УДАЛЕНЫ.</pre>
</div>
<form method="post" action="/">
{hidden_screen("confirm")}
<div class="actions">
<button class="secondary" type="submit" name="action" value="back">Назад</button>
<button type="submit" name="action" value="next">Начать установку</button>
</div>
</form>
"""
    return page(screen_title("confirm"), body)


def render_progress() -> bytes:
    pct, text = 0, "Подготовка..."
    if PROGRESS_PATH.exists():
        try:
            data = json.loads(PROGRESS_PATH.read_text(encoding="utf-8"))
            pct = int(data.get("percent") or 0)
            text = data.get("text") or text
        except Exception:
            pass
    if FINISH_PATH.exists() or pct >= 100:
        state["screen"] = "finish"
        return render_finish()
    width = max(0, min(100, pct))
    body = f"""
<p class="muted">{esc(text)} — {width}%</p>
<div class="bar"><span style="width:{width}%"></span></div>
<p class="muted">Страница обновляется автоматически.</p>
"""
    return page(screen_title("progress"), body, refresh=2)


def render_finish() -> bytes:
    text = ""
    if FINISH_PATH.exists():
        text = FINISH_PATH.read_text(encoding="utf-8")
    body = f"""
<div class="card"><pre style="white-space:pre-wrap;font-family:inherit">{esc(text)}</pre></div>
<form method="post" action="/">
{hidden_screen("finish")}
<div class="actions"><button type="submit" name="action" value="reboot">Перезагрузить</button></div>
</form>
"""
    return page(screen_title("finish"), body)


RENDERERS = {
    "hardware": render_hardware,
    "disk": render_disk,
    "network": render_network,
    "system": render_system,
    "wireguard": render_wireguard,
    "confirm": render_confirm,
    "progress": render_progress,
    "finish": render_finish,
}


def render_step() -> bytes:
    sid = state.get("screen") or first_collect_id()
    # если экран выключен — прыгнуть на ближайший enabled collect
    meta = screen_meta(sid)
    if meta and not meta.get("enabled", True) and meta.get("phase") == "collect":
        nxt = next_collect_id(sid) or first_collect_id()
        state["screen"] = nxt
        sid = nxt
    fn = RENDERERS.get(sid)
    if not fn:
        state["screen"] = first_collect_id()
        fn = RENDERERS[state["screen"]]
    return fn()


def save_config_and_done() -> None:
    RUN_DIR.mkdir(parents=True, exist_ok=True)
    cfg = {
        "disk": state["disk"],
        "mirror_disk": state["mirror_disk"] if state.get("mirror_mode") == "raid1" else "",
        "network": {
            "interface": state["iface"],
            "mode": state["net_mode"],
            "address": state.get("net_addr") or "",
            "gateway": state.get("net_gw") or "",
            "dns": state.get("net_dns") or "9.9.9.9",
        },
        "hostname": state["hostname"],
        "admin": {"user": state["admin_user"], "password": state["admin_pass"]},
        "ssh_enabled": state["ssh"],
        "timezone": state["timezone"],
        "wireguard": {
            "enabled": state["wg"],
            "address": state.get("wg_addr") or "10.66.66.1/24",
            "listen_port": state.get("wg_port") or "51820",
        },
        "mikopbx": {
            "name": state["pbx_name"],
            "web_admin_login": "admin",
            "web_admin_password": state.get("pbx_pass") or "",
        },
        "confirm": "yes",
        "kernel_args": "",
    }
    CONFIG_PATH.write_text(json.dumps(cfg, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    DONE_FLAG.write_text("ok\n", encoding="utf-8")


def go_next(sid: str) -> None:
    nxt = next_collect_id(sid)
    if nxt:
        state["screen"] = nxt
    else:
        state["screen"] = "progress"


def validate_and_advance(form: dict) -> None:
    state["error"] = ""
    action = (form.get("action") or ["next"])[0]
    sid = (form.get("screen") or [state.get("screen") or first_collect_id()])[0]
    if action == "back":
        prev = prev_collect_id(sid)
        if prev:
            state["screen"] = prev
        return
    if action == "reboot":
        DONE_FLAG.write_text("reboot\n", encoding="utf-8")
        return

    if sid == "hardware":
        hw = probe("hardware")
        if hw.get("boot_mode") != "UEFI":
            state["error"] = "Требуется UEFI."
            return
        go_next(sid)
        return

    if sid == "disk":
        state["disk"] = (form.get("disk") or [""])[0]
        state["mirror_mode"] = (form.get("mirror_mode") or ["single"])[0]
        state["mirror_disk"] = (form.get("mirror_disk") or [""])[0]
        if not state["disk"]:
            state["error"] = "Выберите диск."
            return
        if state["mirror_mode"] == "raid1" and not state["mirror_disk"]:
            state["error"] = "Для RAID1 укажите второй диск."
            return
        if state["mirror_mode"] != "raid1":
            state["mirror_disk"] = ""
        go_next(sid)
        return

    if sid == "network":
        state["iface"] = (form.get("iface") or [""])[0]
        state["net_mode"] = (form.get("net_mode") or ["dhcp"])[0]
        state["net_addr"] = (form.get("net_addr") or [""])[0]
        state["net_gw"] = (form.get("net_gw") or [""])[0]
        state["net_dns"] = (form.get("net_dns") or ["9.9.9.9"])[0]
        if not state["iface"]:
            state["error"] = "Выберите интерфейс."
            return
        if state["net_mode"] == "static" and (not state["net_addr"] or not state["net_gw"]):
            state["error"] = "Для static укажите адрес и шлюз."
            return
        go_next(sid)
        return

    if sid == "system":
        state["hostname"] = (form.get("hostname") or ["vlanit-pbx"])[0].strip() or "vlanit-pbx"
        state["admin_user"] = (form.get("admin_user") or ["vlanit"])[0].strip() or "vlanit"
        ap = (form.get("admin_pass") or [""])[0]
        if ap:
            state["admin_pass"] = ap
        state["ssh"] = (form.get("ssh") or ["yes"])[0]
        state["timezone"] = (form.get("timezone") or ["Europe/Moscow"])[0].strip()
        state["pbx_name"] = (form.get("pbx_name") or ["VLANit-PBX"])[0]
        state["pbx_pass"] = (form.get("pbx_pass") or [""])[0]
        if len(state["admin_pass"]) < 8:
            state["error"] = "Пароль короче 8 символов."
            return
        tz_path = Path("/usr/share/zoneinfo") / state["timezone"]
        if not tz_path.is_file():
            state["error"] = f"Неизвестный часовой пояс: {state['timezone']}"
            return
        go_next(sid)
        return

    if sid == "wireguard":
        state["wg"] = (form.get("wg") or ["no"])[0]
        state["wg_addr"] = (form.get("wg_addr") or ["10.66.66.1/24"])[0].strip() or "10.66.66.1/24"
        state["wg_port"] = (form.get("wg_port") or ["51820"])[0].strip() or "51820"
        if state["wg"] == "yes" and not state["wg_port"].isdigit():
            state["error"] = "Порт WireGuard — целое число."
            return
        go_next(sid)
        return

    if sid == "confirm":
        save_config_and_done()
        state["screen"] = "progress"
        return


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args) -> None:
        sys.stderr.write("[gui] " + (fmt % args) + "\n")

    def do_GET(self) -> None:
        path = urllib.parse.urlparse(self.path).path
        if path.startswith("/static/"):
            return self._file(STATIC, path[len("/static/") :])
        if path.startswith("/branding/"):
            return self._file(BRAND_DIR, path[len("/branding/") :])
        if path == "/progress":
            data = b'{"percent":0,"text":"..."}'
            if PROGRESS_PATH.exists():
                data = PROGRESS_PATH.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        if MODE == "progress":
            body = render_progress()
        elif MODE == "finish":
            body = render_finish()
        else:
            body = render_step()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self) -> None:
        length = int(self.headers.get("Content-Length", "0") or 0)
        raw = self.rfile.read(length).decode("utf-8", errors="replace")
        form = urllib.parse.parse_qs(raw, keep_blank_values=True)
        if MODE == "collect":
            validate_and_advance(form)
        elif MODE == "finish":
            action = (form.get("action") or [""])[0]
            if action == "reboot":
                DONE_FLAG.write_text("reboot\n", encoding="utf-8")
        body = render_step()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _file(self, base: Path, rel: str) -> None:
        rel = rel.lstrip("/")
        if not rel or ".." in rel.split("/"):
            self.send_error(404)
            return
        path = (base / rel).resolve()
        try:
            path.relative_to(base.resolve())
        except ValueError:
            self.send_error(404)
            return
        if not path.is_file():
            self.send_error(404)
            return
        data = path.read_bytes()
        ctype = "application/octet-stream"
        if path.suffix == ".css":
            ctype = "text/css; charset=utf-8"
        elif path.suffix == ".svg":
            ctype = "image/svg+xml"
        elif path.suffix == ".png":
            ctype = "image/png"
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


def main() -> int:
    RUN_DIR.mkdir(parents=True, exist_ok=True)
    if MODE == "collect" and DONE_FLAG.exists():
        DONE_FLAG.unlink()
    httpd = ThreadingHTTPServer((HOST, PORT), Handler)
    print(
        f"[gui] http://{HOST}:{PORT}/ mode={MODE} brand={BRAND_NAME} "
        f"screens={[s['id'] for s in collect_screens()]}",
        flush=True,
    )

    if MODE == "collect":
        def watch_done() -> None:
            while True:
                if DONE_FLAG.exists() and DONE_FLAG.read_text(encoding="utf-8").strip() == "ok":
                    threading.Event().wait(0.5)
                    httpd.shutdown()
                    return
                threading.Event().wait(0.3)

        threading.Thread(target=watch_done, daemon=True).start()

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
