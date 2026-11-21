#!/usr/bin/env bash
# scripts/pull-mikopbx.sh — выгрузка официального образа MikoPBX в payload (на хосте).
# Использует docker только как средство скачивания/экспорта на этапе сборки.
# В целевой ОС Docker отсутствует — используется Podman.
# Источник: config/build.yaml → mikopbx.{image,digest,tag} (issue #12).
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PAYLOAD="$PROJECT_ROOT/build/payload"
CFG="$PROJECT_ROOT/config/build.yaml"

yaml_get() {
    # yaml_get <file> <dotted.path>
    python3 - "$1" "$2" <<'PY'
import sys
try:
    import yaml
except ImportError:
    # fallback без PyYAML: простой sed по ключу последнего сегмента
    path, key = sys.argv[1], sys.argv[2].split(".")[-1]
    import re
    text = open(path, encoding="utf-8").read()
    m = re.search(rf'(?m)^\s*{re.escape(key)}:\s*["\']?([^"\'\n#]+)', text)
    if not m:
        sys.exit(f"ключ {sys.argv[2]} не найден в {path}")
    print(m.group(1).strip().strip('"').strip("'"))
    raise SystemExit(0)
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
cur = data
for part in sys.argv[2].split("."):
    cur = cur[part]
print(cur)
PY
}

IMAGE="$(yaml_get "$CFG" mikopbx.image)"
DIGEST="$(yaml_get "$CFG" mikopbx.digest)"
TAG="$(yaml_get "$CFG" mikopbx.tag)"
TAR_NAME="mikopbx-${TAG}.tar"

[ -n "$IMAGE" ] && [ -n "$DIGEST" ] && [ -n "$TAG" ] || {
    echo "ОШИБКА: mikopbx.image/digest/tag пусты в $CFG" >&2
    exit 1
}

mkdir -p "$PAYLOAD"
cd "$PAYLOAD"

echo "Pull $IMAGE (ожидаемый digest $DIGEST)"
docker pull "$IMAGE"

# Проверка digest после pull (docker обновляет digest при pull)
actual="$(docker inspect --format '{{index .RepoDigests 0}}' "$IMAGE" | sed 's/.*@//')"
if [ "$actual" != "$DIGEST" ]; then
    echo "ОШИБКА: digest образа изменился: $actual (ожидался $DIGEST)" >&2
    echo "Обновите config/build.yaml и config/release-manifest.yaml (см. docs/specs/mikopbx-update.md)." >&2
    exit 1
fi

echo "Экспорт образа -> $TAR_NAME"
docker save "$IMAGE" -o "$TAR_NAME"
zstd -f --rm -19 -T0 "$TAR_NAME" -o "$TAR_NAME.zst"
sha256sum "$TAR_NAME.zst" > "$TAR_NAME.zst.sha256"
rm -f mikopbx.tar.zst mikopbx.tar.zst.sha256
ln -sf "$TAR_NAME.zst" mikopbx.tar.zst
ln -sf "$TAR_NAME.zst.sha256" mikopbx.tar.zst.sha256
cat mikopbx.tar.zst.sha256
echo "Готово: $PAYLOAD/mikopbx.tar.zst"
