# Спека: #64 TUI обрыв после «Диск» (as-built)

Статус: **в работе**.

## Корень

`installer/bin/vlanit-probe` ветка `ifaces`:

```bash
{ … printf …; } | python3 - <<'PY'
for line in sys.stdin: …
PY
```

Heredoc перехватывает stdin у `python3 -` → pipe с интерфейсами
теряется → всегда `{"interfaces":[]}`.

TUI после экрана «Диск» (один диск → skip mirror) открывает
`screen_network` с пустым `SelectView` → процесс падает / выходит без
`install-config.json` → установщик: «не удалось собрать параметры
установки (UI)».

`vlanit.ui=dialog` не использует `vlanit-probe ifaces` — поэтому ставится.

`[]` в строке диска — пустой `tran` (virtio), не чекбокс.

## Решение

1. `ifaces`: данные через `IFACES_RAW` env + heredoc (как `disks`).
2. `list_interfaces` / hardware: срезать `eth0@ifN` → `eth0`.
3. TUI: `probe` без panic; не строить пустые SelectView; явный
   `set_selection(0)`.

## Аудит похожих мест

| Место | Паттерн `| cmd <<` | Статус |
|---|---|---|
| `vlanit-probe ifaces` | да | **исправлено** |
| `vlanit-probe hardware/disks` | env + heredoc | ок |
| `config-json.sh` | `python3 - "$path" <<` (argv) | ок |
| GUI `server.py` → probe ifaces | потребитель бага | чинится вместе с probe |
| dialog collect | свой `list_interfaces` | ок |

## Проверка

- `tests/unit/test-probe-ifaces.sh`
- `vlanit-probe ifaces` → непустой `interfaces` при наличии NIC
- TUI: Диск → Далее → экран «Сеть» (не die UI)
