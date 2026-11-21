#!/usr/bin/env bash
# scripts/40-staging.sh — формирование payload и обновление release-manifest.
# Выполняется внутри build-контейнера от root.
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
STAGING="$BUILD_DIR/iso-staging"
PAYLOAD_SRC="$PROJECT_ROOT/build/payload"
# чистим ТОЛЬКО каталоги, которые наполняются на этом шаге и позже.
# staging/live наполняется шагом 30-initramfs — его трогать нельзя
# (иначе в ISO без vmlinuz/initrd/squashfs, найдено сборкой 1.2.9).
# Удалённые из репо файлы (config/defaults.yaml, #21) оседали именно в
# payload — чистка payload достаточна.
rm -rf "$STAGING/payload" "$STAGING/boot"
mkdir -p "$STAGING/payload" "$STAGING/boot/grub"

log() { printf '[staging] %s\n' "$*"; }

log "копирование payload"
MIKOPBX_TAG="$(sed -n 's/^  tag: //p' "$PROJECT_ROOT/config/build.yaml" | head -1 | tr -d '"')"
[ -n "$MIKOPBX_TAG" ] || { echo "[staging] ОШИБКА: mikopbx.tag не найден в build.yaml" >&2; exit 1; }
MIKOPBX_TAR="mikopbx-${MIKOPBX_TAG}.tar.zst"
cp -a "$PAYLOAD_SRC/golden.tar.zst" "$PAYLOAD_SRC/golden.tar.zst.sha256" "$STAGING/payload/"
cp -a "$PAYLOAD_SRC/$MIKOPBX_TAR" "$PAYLOAD_SRC/${MIKOPBX_TAR}.sha256" "$STAGING/payload/"
# совместимость: symlink mikopbx.tar.zst (как в pull-mikopbx.sh)
ln -sfn "$MIKOPBX_TAR" "$STAGING/payload/mikopbx.tar.zst"
ln -sfn "${MIKOPBX_TAR}.sha256" "$STAGING/payload/mikopbx.tar.zst.sha256"

# версии/defaults для установщика
cp -a "$PROJECT_ROOT/config/build.yaml" "$STAGING/payload/build.yaml"
cp -a "$PROJECT_ROOT/config/release-manifest.yaml" "$STAGING/payload/release-manifest.yaml"

GOLDEN_SHA="$(awk '{print $1}' "$STAGING/payload/golden.tar.zst.sha256")"
MIKOPBX_SHA="$(awk '{print $1}' "$STAGING/payload/${MIKOPBX_TAR}.sha256")"
FACTS="$BUILD_DIR/facts.json"
DEBIAN_VERSION="$(jq -r .debian_version "$FACTS")"
KERNEL_VERSION="$(jq -r .kernel_version "$FACTS")"
PODMAN_VERSION="$(jq -r .podman_version "$FACTS")"

log "release-manifest.yaml"
python3 - "$STAGING/payload/release-manifest.yaml" <<EOF
import sys, datetime
path = sys.argv[1]
text = open(path).read()
repl = {
    "  build_date: null": f"  build_date: \"{datetime.datetime.now(datetime.timezone.utc).isoformat()}\"",
    "  version: null": f"  version: \"$DEBIAN_VERSION\"",
    "  kernel: null": f"  kernel: \"$KERNEL_VERSION\"",
    "podman: null": f"podman: \"$PODMAN_VERSION\"",
    "  golden_tar: null": f"  golden_tar: \"$GOLDEN_SHA\"",
    "  mikopbx_tar: null": f"  mikopbx_tar: \"$MIKOPBX_SHA\"",
}
for k, v in repl.items():
    assert k in text, f"ключ не найден в манифесте: {k}"
    text = text.replace(k, v, 1)
open(path, "w").write(text)
EOF
cat "$STAGING/payload/release-manifest.yaml" > /dev/stderr || true
log "staging сформирован"
