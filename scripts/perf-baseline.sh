#!/usr/bin/env bash
# scripts/perf-baseline.sh — Т11 performance baseline.
# Замер host-side (serial без wall-clock). Не FAIL при отклонении >20%:
# только WARN в stdout и строка в docs/testing.md.
#
#   record   — записать метрики прогона в файл + напечатать строку таблицы
#   format   — напечатать markdown-строку из файла
#   append-docs — вставить/обновить строку в docs/testing.md (маркеры T11)
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCS="$PROJECT_ROOT/docs/testing.md"
START_MARK='<!-- T11-BASELINE-START -->'
END_MARK='<!-- T11-BASELINE-END -->'

die() { echo "FATAL: $*" >&2; exit 2; }

# KEY=VAL на stdin/args → файл; печатает markdown-строку
cmd_record() {
    local out="" version="" date_s="" iso_path="" install_sec="" agent_sec="" iso_to_web_sec="" note=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --out) out="$2"; shift 2 ;;
            --version) version="$2"; shift 2 ;;
            --date) date_s="$2"; shift 2 ;;
            --iso) iso_path="$2"; shift 2 ;;
            --install-sec) install_sec="$2"; shift 2 ;;
            --agent-sec) agent_sec="$2"; shift 2 ;;
            --iso-to-web-sec) iso_to_web_sec="$2"; shift 2 ;;
            --note) note="$2"; shift 2 ;;
            *) die "неизвестный аргумент: $1" ;;
        esac
    done
    [ -n "$out" ] || die "нужен --out FILE"
    version="${version:-unknown}"
    date_s="${date_s:-$(date -u +%Y-%m-%d)}"

    local iso_mib="—"
    if [ -n "$iso_path" ] && [ -f "$iso_path" ]; then
        local bytes
        bytes="$(stat -c%s "$iso_path")"
        iso_mib="$(( (bytes + 512*1024) / (1024*1024) ))"
    fi

    {
        echo "version=$version"
        echo "date=$date_s"
        echo "iso_mib=$iso_mib"
        echo "install_sec=${install_sec:-}"
        echo "agent_sec=${agent_sec:-}"
        echo "iso_to_web_sec=${iso_to_web_sec:-}"
        # %q — пробелы в note (напр. «T2 QEMU …») иначе ломают source в format/append
        printf 'note=%q\n' "${note:-}"
        [ -n "$iso_path" ] && printf 'iso_path=%q\n' "$iso_path"
    } > "$out"

    cmd_format "$out"
    _warn_delta "$out" || true
}

cmd_format() {
    local f="$1"
    [ -f "$f" ] || die "нет файла $f"
    # shellcheck disable=SC1090
    set -a; . "$f"; set +a
    local _e='—'
    printf '| %s | %s | %s | %s | %s | %s | %s |\n' \
        "${date:-$_e}" "${version:-$_e}" "${iso_mib:-$_e}" \
        "${install_sec:-$_e}" "${agent_sec:-$_e}" "${iso_to_web_sec:-$_e}" \
        "${note:-}"
}

# Сравнить числовые поля с предыдущей строкой таблицы в docs (если есть).
_warn_delta() {
    local f="$1"
    [ -f "$DOCS" ] || return 0
    # shellcheck disable=SC1090
    set -a; . "$f"; set +a
    local prev
    prev="$(awk -v s="$START_MARK" -v e="$END_MARK" '
        $0==s {inb=1; next}
        $0==e {inb=0}
        inb && /^\| [0-9]{4}-/ {line=$0}
        END {print line}
    ' "$DOCS")"
    [ -n "$prev" ] || return 0

    _cmp_field() {
        local name="$1" cur="$2" col="$3"
        [[ "$cur" =~ ^[0-9]+$ ]] || return 0
        local old
        old="$(printf '%s\n' "$prev" | awk -F'|' -v c="$col" '{gsub(/^ +| +$/,"",$c); print $c}')"
        [[ "$old" =~ ^[0-9]+$ ]] || return 0
        local delta pct
        delta=$(( cur - old ))
        # |delta|/old > 20%
        pct=$(( (delta < 0 ? -delta : delta) * 100 / old ))
        if [ "$pct" -gt 20 ]; then
            echo "WARN Т11: $name=$cur (было $old, Δ ${delta}, ${pct}%) — разобрать, не FAIL" >&2
        fi
    }
    # cols: 1 empty, 2 date, 3 version, 4 iso_mib, 5 install, 6 agent, 7 iso_to_web
    _cmp_field iso_mib "${iso_mib:-}" 4
    _cmp_field install_sec "${install_sec:-}" 5
    _cmp_field agent_sec "${agent_sec:-}" 6
    _cmp_field iso_to_web_sec "${iso_to_web_sec:-}" 7
}

cmd_append_docs() {
    local f="$1"
    [ -f "$f" ] || die "нет файла $f"
    [ -f "$DOCS" ] || die "нет $DOCS"
    local row
    row="$(cmd_format "$f")"
    if ! grep -qF "$START_MARK" "$DOCS"; then
        die "в $DOCS нет маркеров T11 ($START_MARK)"
    fi
    # WARN до вставки: иначе «предыдущая» строка = только что записанная
    _warn_delta "$f" || true
    # вставить строку перед END_MARK (после существующих строк таблицы)
    local tmp
    tmp="$(mktemp)"
    awk -v row="$row" -v e="$END_MARK" '
        $0==e && !done { print row; done=1 }
        { print }
    ' "$DOCS" > "$tmp"
    mv "$tmp" "$DOCS"
    echo "Т11: строка добавлена в docs/testing.md"
}

case "${1:-}" in
    record) shift; cmd_record "$@" ;;
    format) shift; cmd_format "${1:?file}" ;;
    append-docs) shift; cmd_append_docs "${1:?file}" ;;
    *)
        echo "usage: $0 record --out FILE [--version V] [--iso PATH] [--install-sec N] [--agent-sec N] [--iso-to-web-sec N] [--note TEXT]" >&2
        echo "       $0 format FILE" >&2
        echo "       $0 append-docs FILE" >&2
        exit 2
        ;;
esac
