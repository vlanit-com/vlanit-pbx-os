## 1. Config + script

- [x] 1.1 Добавить `output.iso_baseline_mib` / `output.iso_size_margin_pct` в `config/build.yaml` (baseline от v1.4.1 ≈898)
- [x] 1.2 Реализовать `scripts/check-iso-size.sh` (порог, лог, top-N best-effort)
- [x] 1.3 Smoke: tmp-файл under/over → exit 0/1

## 2. CI + docs

- [x] 2.1 Шаг в `.github/workflows/build-iso.yml` после `make iso`
- [x] 2.2 As-built `docs/specs/iso-size-guard.md`; строка в `docs/agent/release-ci.md`
- [x] 2.3 `openspec validate ci-iso-size-guard`; checkpoint

## 3. Out of scope here

- [ ] 3.1 Полный `make iso` / QEMU — отдельная сессия / CI на теге (не блокер merge скрипта)
