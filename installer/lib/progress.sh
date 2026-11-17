# Прогресс-установки: фирменный gauge-диалог со статусами и оценкой
# оставшегося времени. Только интерактивный режим (без AUTOMODE — там
# вывод идёт в консоль/serial для агента).
#
# Протокол dialog --gauge: процент строкой, затем блок XXX\nтекст\nXXX.
# progress_stage дописывает в fd 9; gauge перечитывает сам.

PROGRESS_GAUGE_PID=""
PROGRESS_START=0

# progress_begin <заголовок>
progress_begin() {
    local title="$1" fifo
    fifo="$(mktemp -u)"
    mkfifo "$fifo"
    command dialog --backtitle "$DIALOG_BACKTITLE" --title "$title" \
        --gauge "Подготовка..." 12 74 0 < "$fifo" &
    PROGRESS_GAUGE_PID=$!
    # дескриптор держит fifo открытым; читатель (gauge) не получает EOF,
    # пока мы сами не закроем (progress_end/progress_abort)
    exec 9>"$fifo"
    rm -f "$fifo"
    PROGRESS_START="$(date +%s)"
    log "прогресс-установки: gauge открыт"
}

# progress_stage <pct 0..100> <статус>
# Оценка «осталось ~N мин» — линейная от прошедшего времени и доли
# выполненного; обновляется на каждом вызове (каждый тик).
progress_stage() {
    local pct="$1" text="$2" now elapsed eta=""
    now="$(date +%s)"
    elapsed=$(( now - PROGRESS_START ))
    if [ "$pct" -ge 3 ] && [ "$pct" -lt 100 ]; then
        eta_min=$(( elapsed * (100 - pct) / pct / 60 ))
        eta=" · осталось ~${eta_min} мин"
    fi
    printf '%s\nXXX\n%s%s\nXXX\n' "$pct" "$text" "$eta" >&9 2>/dev/null || true
    log "прогресс: $pct% $text"
}

# progress_end — 100%, закрыть gauge и дождаться его завершения
progress_end() {
    progress_stage 100 "Готово"
    exec 9>&- 2>/dev/null || true
    wait "$PROGRESS_GAUGE_PID" 2>/dev/null || true
    PROGRESS_GAUGE_PID=""
}

# run_stage <pct> <статус> <команда...>
# Один этап установки: тик прогресса, команда с выводом в журнал.
# В интерактиве stdout/stderr этапа уходят в LOG_FILE (иначе мусор
# попадёт на экран gauge); в autoinstall вывод остаётся на консоли.
run_stage() {
    local pct="$1" text="$2"
    shift 2
    progress_stage "$pct" "$text"
    if [ -n "$AUTOMODE" ]; then
        "$@"
    else
        # stdin — /dev/null: tty0 занят gauge-диалогом, чтение из него
        # зависло бы навсегда (интерактив-регрессия 1.3.2)
        { "$@" >> "$LOG_FILE" 2>&1; } </dev/null || { progress_abort; die "сбой этапа: $text"; }
    fi
}

# stage_with_size_progress <pct_from> <pct_to> <статус> <целевой каталог>
#   <полный размер, байты> <команда...>
# Долгий этап с честным суб-прогрессом: команда в фоне, каждые 2 с
# измеряем du целевого каталога и двигаем процент пропорционально
# заполнению (знаменатель — распакованный размер из release-manifest,
# проставляется сборкой). Ошибка команды — abort + die.
stage_with_size_progress() {
    local from="$1" to="$2" text="$3" target="$4" total="$5"
    shift 5
    log "этап (size-progress $from→$to %): $text"
    "$@" >> "$LOG_FILE" 2>&1 </dev/null &
    local pid=$! cur pct
    while kill -0 "$pid" 2>/dev/null; do
        cur="$(du -sb "$target" 2>/dev/null | awk '{print $1}')"
        if [ -n "$total" ] && [ "$total" -gt 0 ] && [ -n "$cur" ]; then
            pct=$(( from + cur * (to - from) / total ))
            [ "$pct" -gt "$to" ] && pct="$to"
        else
            pct="$from"
        fi
        progress_stage "$pct" "$text"
        sleep 2
    done
    if ! wait "$pid"; then
        progress_abort
        die "сбой этапа: $text"
    fi
    progress_stage "$to" "$text"
}
