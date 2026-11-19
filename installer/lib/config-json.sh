# Загрузка/сохранение install-config.json → переменные установщика.
# Контракт UI ↔ bash stages (идея #12).

CONFIG_JSON_DEFAULT="/run/vlanit/install-config.json"

# config_json_save <path> — записать текущие переменные в JSON
config_json_save() {
    local path="${1:-$CONFIG_JSON_DEFAULT}"
    mkdir -p "$(dirname "$path")"
    python3 - "$path" <<'PY'
import json, os, sys
path = sys.argv[1]
data = {
    "disk": os.environ.get("TARGET_DISK", ""),
    "mirror_disk": os.environ.get("MIRROR_DISK", ""),
    "system_size_pct": os.environ.get("SYS_SIZE_PCT_OVERRIDE", ""),
    "network": {
        "interface": os.environ.get("NET_IFACE", ""),
        "mode": os.environ.get("NET_MODE", "dhcp"),
        "address": os.environ.get("NET_ADDR", ""),
        "gateway": os.environ.get("NET_GW", ""),
        "dns": os.environ.get("NET_DNS", "9.9.9.9"),
    },
    "hostname": os.environ.get("SYS_HOSTNAME", "vlanit-pbx"),
    "admin": {
        "user": os.environ.get("ADMIN_USER", "vlanit"),
        "password": os.environ.get("ADMIN_PASS", ""),
    },
    "ssh_enabled": os.environ.get("SSH_ENABLED", "yes"),
    "timezone": os.environ.get("TZ_NAME", "UTC"),
    "wireguard": {
        "enabled": os.environ.get("WG_ENABLED", "no"),
        "address": os.environ.get("WG_ADDR", "10.66.66.1/24"),
        "listen_port": os.environ.get("WG_PORT", "51820"),
    },
    "mikopbx": {
        "name": os.environ.get("PBX_NAME", "VLANit-PBX"),
        "web_admin_login": os.environ.get("PBX_ADMIN_LOGIN", "admin"),
        "web_admin_password": os.environ.get("PBX_ADMIN_PASS", ""),
    },
    "confirm": "yes",
    "kernel_args": os.environ.get("KERNEL_ARGS", ""),
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write("\n")
PY
}

# config_json_load <path> — выставить TARGET_DISK, NET_*, … из JSON
config_json_load() {
    local path="${1:-$CONFIG_JSON_DEFAULT}"
    [ -f "$path" ] || die "нет конфига: $path"
    eval "$(python3 - "$path" <<'PY'
import json, shlex, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
net = d.get("network") or {}
admin = d.get("admin") or {}
wg = d.get("wireguard") or {}
pbx = d.get("mikopbx") or {}

def exp(name, val):
    print(f"export {name}={shlex.quote('' if val is None else str(val))}")

exp("TARGET_DISK", d.get("disk", ""))
exp("MIRROR_DISK", d.get("mirror_disk", "") or "")
pct = d.get("system_size_pct", "") or ""
exp("SYS_SIZE_PCT_OVERRIDE", pct)
exp("NET_IFACE", net.get("interface", ""))
exp("NET_MODE", net.get("mode", "dhcp") or "dhcp")
exp("NET_ADDR", net.get("address", "") or "")
exp("NET_GW", net.get("gateway", "") or "")
exp("NET_DNS", net.get("dns", "9.9.9.9") or "9.9.9.9")
exp("SYS_HOSTNAME", d.get("hostname", "vlanit-pbx") or "vlanit-pbx")
exp("ADMIN_USER", admin.get("user", "vlanit") or "vlanit")
exp("ADMIN_PASS", admin.get("password", "") or "")
ssh = str(d.get("ssh_enabled", "yes")).lower()
exp("SSH_ENABLED", "yes" if ssh in ("yes", "true", "1") else "no")
exp("TZ_NAME", d.get("timezone", "UTC") or "UTC")
wge = str(wg.get("enabled", "no")).lower()
exp("WG_ENABLED", "yes" if wge in ("yes", "true", "1") else "no")
exp("WG_ADDR", wg.get("address", "10.66.66.1/24") or "10.66.66.1/24")
exp("WG_PORT", str(wg.get("listen_port", "51820") or "51820"))
exp("PBX_NAME", pbx.get("name", "VLANit-PBX") or "VLANit-PBX")
exp("PBX_ADMIN_LOGIN", pbx.get("web_admin_login", "admin") or "admin")
exp("PBX_ADMIN_PASS", pbx.get("web_admin_password", "") or "")
exp("KERNEL_ARGS", d.get("kernel_args", "") or "")
confirm = str(d.get("confirm", "")).lower()
if confirm not in ("yes", "true", "1"):
    sys.stderr.write("config-json: confirm must be yes\n")
    sys.exit(1)
PY
)"
}
