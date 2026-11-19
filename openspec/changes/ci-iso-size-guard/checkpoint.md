# Checkpoint: ci-iso-size-guard

| Поле | Значение |
|---|---|
| OpenSpec change | ci-iso-size-guard (#33) |
| Stage | verify / ready for PR |
| Done (кратко) | OpenSpec 4/4; script+workflow+docs; unit PASS; real 1.4.0 ISO OK (892 MiB < 942.9) |
| Remaining (кратко) | PR/merge; archive change; полный CI на dispatch/теге |
| Files touched | config/build.yaml, scripts/check-iso-size.sh, build-iso.yml, docs/specs/iso-size-guard.md, docs/agent/release-ci.md, tests/unit/test-iso-size-guard.sh, openspec/changes/ci-iso-size-guard/* |
| Last verify | `bash tests/unit/test-iso-size-guard.sh` PASS; check на dist/1.4.0 OK |
| Blockers | нет |
| Next action | commit + PR (workflow scope); не archive до merge |
