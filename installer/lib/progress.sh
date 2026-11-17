# Прогресс-установки: фирменный gauge-диалог со статусами и оценкой
# оставшегося времени. Только интерактивный режим (без AUTOMODE — там
# вывод идёт в консоль/serial для агента).
#
# Протокол dialog --gauge: процент строкой, затем блок XXX\nтекст\nXXX.
# progress_stage дописывает в fd 9; gauge перечитывает сам.

PROGRESS_GAUGE_PID=""
PROGRESS_START=0

# Калибровка ожидаемых длительностей этапов, секунды — из фактических
# прогонов QEMU-стенда (зеркало 2×40 ГиБ). Формат «pct:секунды»: секунды —
# ожидаемая длительность шага, ЗАВЕРШАЮЩЕГОСЯ на отметке pct шкалы
# установщика (installer/vlanit-installer). Линейная от общего процента
# модель давала «~0 мин»: шкала скачковая (13→60 % мгновенно на зеркале,
# загрузчик 95 % идёт ~7 мин при ходе шкалы на 3 п.п.).
PROGRESS_STAGE_SECONDS="3:20 8:35 13:30 60:180 65:90 68:5 70:10 72:10 85:270 95:0 98:450 100:15"
PROGRESS_CUM_EXP=""   # «pct:секунды от начала установки» на точках шкалы
PROGRESS_TOTAL_EXP=0  # ожидаемая полная длительность

# Кумулятивная таблица ожидаемого времени по точкам шкалы — считается из
# PROGRESS_STAGE_SECONDS один раз при открытии gauge.
progress_init_calibration() {
    PROGRESS_CUM_EXP="$(awk -v stages="$PROGRESS_STAGE_SECONDS" 'BEGIN{
        n=split(stages, a, " "); cum=0; printf "0:0";
        for (i = 1; i <= n; i++) {
            split(a[i], kv, ":"); cum += kv[2]; printf " %s:%d", kv[1], cum
        }
        printf "\n"
    }')"
    PROGRESS_TOTAL_EXP="${PROGRESS_CUM_EXP##* }"
    PROGRESS_TOTAL_EXP="${PROGRESS_TOTAL_EXP#*:}"
}

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
    progress_init_calibration
    log "прогресс-установки: gauge открыт"
}

# progress_stage <pct 0..100> <статус>
# Оценка «осталось ~N мин» — кусочно-линейная по калиброванным длительностям
# этапов: ожидаемое пройденное время интерполируется по шкале, поправка
# скорости = elapsed/ожидаемое (кламп 0.25–4). Обновляется на каждом тике.
progress_stage() {
    local pct="$1" text="$2" now elapsed eta=""
    now="$(date +%s)"
    elapsed=$(( now - PROGRESS_START ))
    eta="$(awk -v pct="$pct" -v elapsed="$elapsed" \
              -v knots="$PROGRESS_CUM_EXP" -v total="$PROGRESS_TOTAL_EXP" 'BEGIN{
        if (pct < 3 || pct >= 100) exit
        m=split(knots, a, " "); prev_pct=0; prev_cum=0; done=-1
        for (i = 1; i <= m; i++) {
            split(a[i], kv, ":"); kp=kv[1]+0; kc=kv[2]+0
            if (kp == pct) { done=kc; break }
            if (kp > pct) {
                done=prev_cum+(pct-prev_pct)*(kc-prev_cum)/(kp-prev_pct); break
            }
            prev_pct=kp; prev_cum=kc
        }
        if (done < 0) done=prev_cum
        if (done <= 0) exit
        corr=elapsed/done
        if (corr < 0.25) corr=0.25
        if (corr > 4) corr=4
        remaining=int((total-done)*corr)
        if (remaining < 60) printf " · осталось <1 мин"
        else printf " · осталось ~%d мин", int((remaining+30)/60)
    }')"
    printf '%s\nXXX\n%s%s\nXXX\n' "$pct" "$text" "$eta" >&9 2>/dev/null || true
    log "прогресс: $pct% $text$eta"
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
#
# Суб-прогресс по du для долгих этапов УДАЛЁН (1.3.2): фоновый du по
# целевой ФС во время распаковки дважды уходил в D-state навсегда
# (зеркало и однодисковый режим, serial молчал часами). Этапы идут
# скачком; плавность времени даёт калиброванная ETA-таблица выше.
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
