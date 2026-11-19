## Purpose

Проверка размера собранного ISO против baseline из конфига сборки с
допуском margin %, чтобы CI ловил регрессии размера до публикации релиза.

## ADDED Requirements

### Requirement: Baseline and margin in build config

`config/build.yaml` MUST define under `output:` integer
`iso_baseline_mib` and numeric `iso_size_margin_pct` (default intent 5).
The size guard MUST read these keys as the sole source of the fail
threshold: `ceil_bytes = baseline_mib * (100 + margin_pct) / 100 * 1 MiB`.

#### Scenario: Config keys present for consumers

- **WHEN** an agent or CI runs the size guard
- **THEN** it reads `output.iso_baseline_mib` and
  `output.iso_size_margin_pct` from `config/build.yaml` (not hardcoded
  limits in the workflow YAML)

### Requirement: Size guard script

The repository MUST provide `scripts/check-iso-size.sh` that accepts an
ISO path (or discovers `dist/*.iso`), prints the size in bytes and MiB,
compares to the configured threshold, and exits non-zero if the ISO is
strictly larger than the threshold. The script MUST print diagnostic
top largest members inside the ISO when a suitable tool is available;
missing diagnostic tools MUST NOT alone cause failure.

#### Scenario: ISO within limit

- **WHEN** the ISO byte size is less than or equal to the threshold
- **THEN** the script exits 0 and prints size and threshold

#### Scenario: ISO over limit

- **WHEN** the ISO byte size is greater than the threshold
- **THEN** the script exits non-zero with an explicit over-limit message

### Requirement: CI build-iso invokes the guard

`.github/workflows/build-iso.yml` MUST run the size guard after a
successful `make iso` and before release publication. A failing guard
MUST fail the job.

#### Scenario: Guard step after ISO build

- **WHEN** the `build-iso` workflow finishes `make iso` successfully
- **THEN** a subsequent step runs `scripts/check-iso-size.sh` on the
  produced ISO
