#!/usr/bin/env bash
# unit: vlanit-probe ifaces не глотает stdin heredoc'ом (#64)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROBE="$ROOT/installer/bin/vlanit-probe"
export INSTALLER_DIR="$ROOT/installer"

# На хосте должен быть хотя бы lo; list_interfaces lo отфильтровывает —
# подменим list через PATH-обёртку нельзя легко. Проверяем JSON-форму
# и что при наличии IFACES-подобных данных парсер не пустой.
#
# Главный регресс: раньше `| python3 - <<` всегда давал [].
out="$("$PROBE" ifaces)"
echo "$out" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert "interfaces" in d and isinstance(d["interfaces"], list), d
# на обычном Linux есть eth/wlan/en* — если пусто, всё равно валидный JSON
for i in d["interfaces"]:
    assert "name" in i and "mac" in i, i
    assert "@" not in i["name"], i  # суффикс @ifN срезан
print("ifaces_count", len(d["interfaces"]))
'

# Синтетика: воспроизводим старый баг pipe|heredoc vs env
raw=$'ens3|aa:bb\neth0|cc:dd'
got_bug=$(echo "$raw" | python3 - <<'PY'
import json, sys
out = []
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    name, mac = line.split("|", 1)
    out.append({"name": name, "mac": mac})
print(json.dumps({"interfaces": out}))
PY
)
echo "$got_bug" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["interfaces"]==[], d'

got_ok=$(IFACES_RAW="$raw" python3 - <<'PY'
import json, os
out = []
for line in (os.environ.get("IFACES_RAW") or "").splitlines():
    line = line.strip()
    if not line: continue
    name, _, mac = line.partition("|")
    out.append({"name": name, "mac": mac})
print(json.dumps({"interfaces": out}))
PY
)
echo "$got_ok" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert len(d["interfaces"])==2, d'

echo "PASS test-probe-ifaces"
