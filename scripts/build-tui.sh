#!/usr/bin/env bash
# scripts/build-tui.sh — сборка vlanit-tui (Cursive) → installer/bin/vlanit-tui.
# Предпочтительно: официальный образ rust (не раздувает vlanit-build).
# Fallback: cargo на хосте. Нет cargo/docker — пропуск (dialog fallback).
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CRATE="$PROJECT_ROOT/installer/tui-cursive"
OUT="$PROJECT_ROOT/installer/bin/vlanit-tui"
RUST_IMAGE="${VLANIT_RUST_IMAGE:-rust:1.85-bookworm}"

build_local() {
    ( cd "$CRATE" && cargo build --release )
    install -D -m 0755 "$CRATE/target/release/vlanit-tui" "$OUT"
}

build_docker() {
    docker run --rm \
        -v "$CRATE:/crate" \
        -v "$CRATE/target:/crate/target" \
        -w /crate \
        "$RUST_IMAGE" \
        cargo build --release
    install -D -m 0755 "$CRATE/target/release/vlanit-tui" "$OUT"
}

mkdir -p "$CRATE/target" "$(dirname "$OUT")"

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    echo "[tui] docker $RUST_IMAGE"
    if build_docker; then
        echo "[tui] → $OUT ($(du -h "$OUT" | awk '{print $1}'))"
        exit 0
    fi
    echo "[tui] docker build failed — пробую host cargo" >&2
fi

if command -v cargo >/dev/null 2>&1; then
    echo "[tui] host cargo"
    build_local
    echo "[tui] → $OUT ($(du -h "$OUT" | awk '{print $1}'))"
    exit 0
fi

echo "[tui] нет docker/cargo — пропускаю (dialog останется fallback)" >&2
exit 0
