# Спека: обновление MikoPBX в образе (issue #12)

Статус: **as-built**.

## 0. Корень

Версия MikoPBX зафиксирована в образе (тег + digest). Нужен регламент
мониторинга upstream и безопасного bump без «размазанных» литералов.

## 1. Решение

Единый источник: `config/build.yaml` → `mikopbx.{image,digest,tag,local_name}`.
Зеркало для манифеста: `config/release-manifest.yaml` → `mikopbx.*`
(то же image/version/digest; version = tag без `-amd64`).

Потребители читают YAML (не хардкод тега):

| Кто | Откуда |
|---|---|
| `scripts/pull-mikopbx.sh` | `config/build.yaml` |
| `scripts/40-staging.sh` | `config/build.yaml` → имя `mikopbx-<tag>.tar.zst` |
| установщик (`deploy` / `install-run`) | `payload/build.yaml` |
| `vlanit-firstboot` | `/var/lib/vlanit/payload/build.yaml` |

Процедура bump (кратко; подробно — § ниже и troubleshooting):

1. Мониторинг Docker Hub `mikopbx/mikopbx` (stable `*-amd64`, не `*-dev`).
2. Changelog / upstream-фиксы (в т.ч. WEB_ADMIN_PASSWORD / #10).
3. Обновить `build.yaml` + `release-manifest.yaml` (image, tag, local_name, digest).
4. `bash scripts/pull-mikopbx.sh` — pull + verify digest + export tar.zst.
5. `make iso` → `bash scripts/check-iso-size.sh dist/<iso>` (bump baseline при росте).
6. QEMU: минимум Т1+Т2; перед релизом — Т1–Т9 / `regress-full` по матрице.
7. Критерий: агент PASS; `vlanit-doctor --quiet` = 0 (WARN ок);
   upstream reboot-api-login может остаться WARN-CHECK.
8. Релиз: bump `distro.version` везде + CHANGELOG + тег (см. release-ci).

## 2. Отклонённые

- Следовать `latest` без pin digest — нет воспроизводимости ISO.
- Dev-теги (`*-dev`) в релизе — нестабильны.
- Авто-bump в CI без ручного review changelog — слишком рискованно.

## 3. Проверка

```bash
# digest из build.yaml совпадает с Hub после pull
bash scripts/pull-mikopbx.sh
# unit (если есть) + ISO + QEMU T2
make iso && bash scripts/test-qemu.sh boot && bash scripts/test-qemu.sh install
```
