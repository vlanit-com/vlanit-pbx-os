#!/usr/bin/env bash
# scripts/regress-full.sh — полный регресс VLANit PBX OS: Т1–Т9 + mirror.
# Сценарии идут по одному; между ними каталоги прошлых прогонов удаляются
# (qcow2 зеркала разрастаются до ~20 ГБ на прогон; диск хоста ограничен).
# При FAIL прогона — остановка, каталог прогона сохранён для разбора.
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/.."

FAILED=0
scenarios=("$@")
[ "${#scenarios[@]}" -eq 0 ] && scenarios=(boot install offline errors ota backup mirror)
for s in "${scenarios[@]}"; do
    echo "=== регресс: $s ($(date +%H:%M:%S)) ==="
    if ! KEEP_RUNS=1 bash scripts/test-qemu.sh "$s"; then
        echo "РЕГРЕСС ОСТАНОВЛЕН: сценарий '$s' FAIL — каталог прогона сохранён:"
        ls -1dt build/qemu/2* 2>/dev/null | head -1
        exit 1
    fi
    mapfile -t runs < <(ls -1dt build/qemu/2* 2>/dev/null)
    for d in "${runs[@]:1}"; do rm -rf "$d"; done
    df -h /home | tail -1
done
echo "ПОЛНЫЙ РЕГРЕСС ПРОЙДЕН: Т1–Т9 + mirror"
