#!/usr/bin/env bash
# Round-trip install-config.json → env (контракт UI ↔ stages).
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck disable=SC1091
. "$ROOT/installer/lib/common.sh"
# shellcheck disable=SC1091
. "$ROOT/installer/lib/config-json.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
CFG="$TMP/install-config.json"

export TARGET_DISK=/dev/vda MIRROR_DISK="" NET_IFACE=eth0 NET_MODE=dhcp
export NET_ADDR="" NET_GW="" NET_DNS="9.9.9.9"
export SYS_HOSTNAME=test-pbx ADMIN_USER=vlanit ADMIN_PASS=secret123
export SSH_ENABLED=yes TZ_NAME=Europe/Moscow
export WG_ENABLED=no WG_ADDR=10.66.66.1/24 WG_PORT=51820
export PBX_NAME=VLANit-PBX PBX_ADMIN_LOGIN=admin PBX_ADMIN_PASS=""
export KERNEL_ARGS="" SYS_SIZE_PCT_OVERRIDE=""

config_json_save "$CFG"
grep -q '"disk": "/dev/vda"' "$CFG"
grep -q '"hostname": "test-pbx"' "$CFG"

# сброс и загрузка
unset TARGET_DISK SYS_HOSTNAME ADMIN_PASS
config_json_load "$CFG"
[ "$TARGET_DISK" = "/dev/vda" ]
[ "$SYS_HOSTNAME" = "test-pbx" ]
[ "$ADMIN_PASS" = "secret123" ]
[ "$NET_IFACE" = "eth0" ]
echo "PASS test-config-json"
