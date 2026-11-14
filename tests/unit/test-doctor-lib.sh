#!/usr/bin/env bash
# tests/unit/test-doctor-lib.sh — unit-тесты библиотеки проверок (issue #9).
# Проверяем: контракт desc_/hint_/check_ на каждое имя из CHECK_GROUPS,
# коды возврата (0/1/2), SKIP-семантику на моках.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# моки команд (чистая среда теста)
MOCKBIN="$WORK/bin"
mkdir -p "$MOCKBIN"
for c in hostname findmnt ip ss nft curl systemctl podman df getent ls sshd unattended-upgrades fail2ban-client awk grep test; do
    : # не создаём заглушки для builtins/real; только то, что нужно ниже
done

fail=0
ok()   { echo "PASS $1"; }
bad()  { echo "FAIL $1"; fail=1; }

# shellcheck source=../../rootfs/lib-checks.sh
source "$ROOT/rootfs/lib-checks.sh"

# 1. Контракт: для каждой проверки в CHECK_GROUPS есть check_/desc_/hint_
missing=0
for group_def in "${CHECK_GROUPS[@]}"; do
    for name in ${group_def#*:}; do
        for f in check desc hint; do
            if ! declare -F "${f}_${name}" >/dev/null; then
                bad "нет функции ${f}_${name}"; missing=1
            fi
        done
    done
done
[ "$missing" = "0" ] && ok "контракт: все проверки имеют check_/desc_/hint_"

# 2. desc_/hint_ возвращают непустые строки
empty=0
for group_def in "${CHECK_GROUPS[@]}"; do
    for name in ${group_def#*:}; do
        [ -n "$(desc_"$name")" ] || { bad "desc_$name пуст"; empty=1; }
        [ -n "$(hint_"$name")" ] || { bad "hint_$name пуст"; empty=1; }
    done
done
[ "$empty" = "0" ] && ok "desc_/hint_ непустые"

# 3. SKIP-семантика: wireguard не включён -> SKIP(2)
systemctl() { return 4; }
check_wireguard-active; rc=$?
unset -f systemctl
[ "$rc" = "2" ] && ok "wireguard не включён -> SKIP" || bad "wireguard SKIP: rc=$rc"

# 4. hostname: совпадение vlanit
hostname() { echo "vlanit-pbx-test"; }
check_hostname; rc=$?
unset -f hostname
[ "$rc" = "0" ] && ok "hostname vlanit -> OK" || bad "hostname: rc=$rc"

# 5. nft-no-testnet: правила без тестовой подсети -> OK
nft() { echo 'chain input { type filter hook input priority filter; policy drop; }'; }
check_nft-no-testnet; rc=$?
[ "$rc" = "0" ] || bad "nft-no-testnet clean: rc=$rc"
nft() { echo 'ip saddr 10.0.2.0/24 accept'; }
check_nft-no-testnet; rc=$?
unset -f nft
[ "$rc" = "1" ] && ok "nft с тестовой подсетью -> FAIL" || bad "nft-no-testnet detect: rc=$rc"

# 6. disk-space: нет данных df -> SKIP
df() { :; }
check_disk-space; rc=$?
unset -f df
[ "$rc" = "2" ] && ok "disk-space без df -> SKIP" || bad "disk-space SKIP: rc=$rc"

# 7. findmnt btrfs
findmnt() { echo "/ /dev/vda2 btrfs rw,relatime,subvol=/@"; }
check_btrfs-root; rc=$?
unset -f findmnt
[ "$rc" = "0" ] && ok "btrfs-root -> OK" || bad "btrfs-root: rc=$rc"

exit $fail
