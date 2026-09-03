#!/usr/bin/env bash
set -Eeuo pipefail

ISO_PATH="${1:-}"
RESULT_DIR="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

[[ -n "$ISO_PATH" ]] || {
    echo "Использование: $0 /path/to/image.iso /path/to/results" >&2
    exit 2
}
[[ -f "$ISO_PATH" ]] || { echo "ISO не найден: $ISO_PATH" >&2; exit 2; }
[[ -n "$RESULT_DIR" ]] || RESULT_DIR="$SCRIPT_DIR/results"

ISO_PATH="$(readlink -f "$ISO_PATH")"
mkdir -p "$RESULT_DIR"
RESULT_DIR="$(readlink -f "$RESULT_DIR")"
WORK_DIR="$RESULT_DIR/work"
HTTP_ROOT="$WORK_DIR/http"
EXTRACT_DIR="$WORK_DIR/installer"
REPORT="$RESULT_DIR/full-cycle-report.txt"
HTTP_PORT=8080
CI_URL="http://10.0.2.2:$HTTP_PORT/index.html"
PRESEED_URL="http://10.0.2.2:$HTTP_PORT/preseed-ci.cfg"
HTTP_PID=""
CURRENT_QEMU_PID=""
CURRENT_MONITOR=""
CURRENT_SERIAL=""

mkdir -p "$WORK_DIR" "$HTTP_ROOT" "$EXTRACT_DIR"
: >"$REPORT"

log() {
    printf '\n[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$REPORT"
}

pass() {
    printf 'PASS — %s\n' "$*" | tee -a "$REPORT"
}

fail() {
    printf 'FAIL — %s\n' "$*" | tee -a "$REPORT" >&2
    if [[ -n "${CURRENT_SERIAL:-}" && -f "$CURRENT_SERIAL" ]]; then
        printf '\n--- Последние строки serial log ---\n' >&2
        tail -n 160 "$CURRENT_SERIAL" >&2 || true
    fi
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Не найден инструмент: $1"
}

for command_name in \
    qemu-system-x86_64 qemu-img xorriso socat python3 curl grep sed awk timeout; do
    require_command "$command_name"
done

if [[ -r /dev/kvm && -w /dev/kvm ]]; then
    QEMU_ACCEL="kvm"
    QEMU_CPU="host"
else
    QEMU_ACCEL="tcg,thread=multi"
    QEMU_CPU="max"
fi

find_ovmf_pair() {
    local code vars
    for code in \
        /usr/share/OVMF/OVMF_CODE_4M.fd \
        /usr/share/OVMF/OVMF_CODE.fd \
        /usr/share/edk2/ovmf/OVMF_CODE.fd; do
        [[ -f "$code" ]] || continue
        case "$code" in
            *OVMF_CODE_4M.fd) vars="${code/OVMF_CODE_4M.fd/OVMF_VARS_4M.fd}" ;;
            *OVMF_CODE.fd) vars="${code/OVMF_CODE.fd/OVMF_VARS.fd}" ;;
            *) continue ;;
        esac
        if [[ -f "$vars" ]]; then
            OVMF_CODE="$code"
            OVMF_VARS_TEMPLATE="$vars"
            return 0
        fi
    done
    return 1
}

find_ovmf_pair || fail "Не найдена совместимая пара OVMF_CODE/OVMF_VARS"

cleanup_vm() {
    if [[ -n "${CURRENT_QEMU_PID:-}" ]] && kill -0 "$CURRENT_QEMU_PID" 2>/dev/null; then
        if [[ -S "${CURRENT_MONITOR:-}" ]]; then
            printf 'quit\n' | socat - "UNIX-CONNECT:$CURRENT_MONITOR" \
                >/dev/null 2>&1 || true
        fi
        for _ in $(seq 1 30); do
            kill -0 "$CURRENT_QEMU_PID" 2>/dev/null || break
            sleep 0.2
        done
        kill -TERM "$CURRENT_QEMU_PID" 2>/dev/null || true
        sleep 1
        kill -KILL "$CURRENT_QEMU_PID" 2>/dev/null || true
        wait "$CURRENT_QEMU_PID" 2>/dev/null || true
    fi
    CURRENT_QEMU_PID=""
    CURRENT_MONITOR=""
    CURRENT_SERIAL=""
}

cleanup_all() {
    cleanup_vm
    if [[ -n "${HTTP_PID:-}" ]]; then
        kill -TERM "$HTTP_PID" 2>/dev/null || true
        wait "$HTTP_PID" 2>/dev/null || true
    fi
}
trap cleanup_all EXIT INT TERM HUP

wait_for_monitor() {
    local socket="$1" timeout_seconds="${2:-30}"
    local started=$SECONDS
    while (( SECONDS - started < timeout_seconds )); do
        [[ -S "$socket" ]] && return 0
        [[ -n "${CURRENT_QEMU_PID:-}" ]] \
            && kill -0 "$CURRENT_QEMU_PID" 2>/dev/null || return 1
        sleep 0.2
    done
    return 1
}

wait_for_pattern() {
    local file="$1" pattern="$2" timeout_seconds="$3"
    local started=$SECONDS
    while (( SECONDS - started < timeout_seconds )); do
        if [[ -f "$file" ]] && grep -Fq "$pattern" "$file"; then
            return 0
        fi
        if [[ -n "${CURRENT_QEMU_PID:-}" ]] \
           && ! kill -0 "$CURRENT_QEMU_PID" 2>/dev/null; then
            return 1
        fi
        sleep 1
    done
    return 1
}

wait_for_exit() {
    local pid="$1" timeout_seconds="$2"
    local started=$SECONDS
    while (( SECONDS - started < timeout_seconds )); do
        kill -0 "$pid" 2>/dev/null || {
            wait "$pid" 2>/dev/null || true
            return 0
        }
        sleep 1
    done
    return 1
}

hmp() {
    local command_text="$1"
    [[ -S "$CURRENT_MONITOR" ]] || return 1
    printf '%s\n' "$command_text" \
        | socat - "UNIX-CONNECT:$CURRENT_MONITOR" >/dev/null 2>&1
}

capture_screen() {
    local output_base="$1"
    [[ -S "$CURRENT_MONITOR" ]] || return 0
    hmp "screendump $output_base.ppm" || true
    sleep 1
    if [[ -s "$output_base.ppm" ]] && command -v convert >/dev/null 2>&1; then
        convert "$output_base.ppm" "$output_base.png" >/dev/null 2>&1 || true
    fi
}

poweroff_vm() {
    local pid="$CURRENT_QEMU_PID"
    hmp system_powerdown || true
    if wait_for_exit "$pid" 45; then
        CURRENT_QEMU_PID=""
        CURRENT_MONITOR=""
        CURRENT_SERIAL=""
        return 0
    fi
    hmp quit || true
    if wait_for_exit "$pid" 15; then
        CURRENT_QEMU_PID=""
        CURRENT_MONITOR=""
        CURRENT_SERIAL=""
        return 0
    fi
    cleanup_vm
}

firmware_args() {
    local firmware="$1" vars_path="$2"
    FIRMWARE_ARGS=()
    if [[ "$firmware" == uefi ]]; then
        FIRMWARE_ARGS=(
            -machine q35
            -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE"
            -drive "if=pflash,format=raw,file=$vars_path"
        )
    else
        FIRMWARE_ARGS=(-machine pc)
    fi
}

start_qemu() {
    local name="$1" firmware="$2" vars_path="$3"
    shift 3

    cleanup_vm
    CURRENT_SERIAL="$RESULT_DIR/$name-serial.log"
    CURRENT_MONITOR="$WORK_DIR/$name-monitor.sock"
    rm -f "$CURRENT_SERIAL" "$CURRENT_MONITOR"
    : >"$CURRENT_SERIAL"

    firmware_args "$firmware" "$vars_path"

    qemu-system-x86_64 \
        -name "$name" \
        "${FIRMWARE_ARGS[@]}" \
        -accel "$QEMU_ACCEL" \
        -cpu "$QEMU_CPU" \
        -m 2048 \
        -smp 2 \
        -rtc base=utc \
        -vga std \
        -display none \
        -serial "file:$CURRENT_SERIAL" \
        -monitor "unix:$CURRENT_MONITOR,server=on,wait=off" \
        -nic user,model=virtio-net-pci \
        -no-reboot \
        "$@" \
        >"$RESULT_DIR/$name-qemu.log" 2>&1 &
    CURRENT_QEMU_PID=$!

    wait_for_monitor "$CURRENT_MONITOR" 30 \
        || fail "$name: QEMU monitor не появился"
}

extract_iso_file() {
    local destination="$1"
    shift
    local candidate
    for candidate in "$@"; do
        rm -f "$destination"
        if xorriso -osirrox on -indev "$ISO_PATH" \
            -extract "$candidate" "$destination" \
            >"$destination.xorriso.log" 2>&1 \
            && [[ -s "$destination" ]]; then
            printf '%s\n' "$candidate" >"$destination.source-path"
            return 0
        fi
    done
    return 1
}

log "Исходные данные"
printf 'ISO: %s\n' "$ISO_PATH" | tee -a "$REPORT"
printf 'SHA-256: %s\n' "$(sha256sum "$ISO_PATH" | awk '{print $1}')" | tee -a "$REPORT"
printf 'QEMU accelerator: %s\n' "$QEMU_ACCEL" | tee -a "$REPORT"
printf 'OVMF code: %s\n' "$OVMF_CODE" | tee -a "$REPORT"
printf 'OVMF vars: %s\n' "$OVMF_VARS_TEMPLATE" | tee -a "$REPORT"

log "Статическая проверка ISO"
xorriso -indev "$ISO_PATH" -report_el_torito plain \
    >"$RESULT_DIR/el-torito.txt" 2>&1 \
    || fail "xorriso не смог прочитать El Torito"
grep -Eiq 'El Torito|boot' "$RESULT_DIR/el-torito.txt" \
    || fail "В отчёте отсутствует загрузочная структура"
pass "ISO содержит загрузочную структуру El Torito"

extract_iso_file "$EXTRACT_DIR/installer-vmlinuz" \
    /install.amd/vmlinuz /install/vmlinuz /install.amd/linux /install/linux \
    || fail "Не удалось извлечь ядро Debian Installer"
extract_iso_file "$EXTRACT_DIR/installer-initrd" \
    /install.amd/initrd.gz /install/initrd.gz /install.amd/initrd /install/initrd \
    || fail "Не удалось извлечь initrd Debian Installer"
extract_iso_file "$EXTRACT_DIR/filesystem.squashfs" \
    /live/filesystem.squashfs \
    || fail "Не удалось извлечь filesystem.squashfs"
pass "Из точного ISO извлечены Debian Installer и live SquashFS"

unsquashfs -ll "$EXTRACT_DIR/filesystem.squashfs" \
    >"$RESULT_DIR/squashfs-files.txt" 2>&1 \
    || fail "filesystem.squashfs не читается"
for required_path in \
    usr/sbin/lightdm \
    opt/op-kiosk/session.sh \
    opt/op-kiosk/browser-supervisor.sh \
    opt/op-kiosk/admin-menu.sh \
    usr/local/sbin/op-kiosk-finalize; do
    grep -Fq "$required_path" "$RESULT_DIR/squashfs-files.txt" \
        || fail "В SquashFS отсутствует $required_path"
done
if grep -Fq 'usr/local/sbin/op-kiosk-install' "$RESULT_DIR/squashfs-files.txt"; then
    fail "В версии 2.0 не должен присутствовать старый самописный установщик"
fi
pass "Старый самописный установщик исключён; LightDM и kiosk-компоненты присутствуют"

log "Подготовка CI HTTP-сервера"
sed "s|@@CI_URL@@|$CI_URL|g" "$SCRIPT_DIR/preseed-ci.cfg" \
    >"$HTTP_ROOT/preseed-ci.cfg"
cat >"$HTTP_ROOT/index.html" <<'EOF'
<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>OP Kiosk CI Ready</title></head>
<body><h1>OP Kiosk CI Ready</h1><p id="marker">OP_KIOSK_CI_PAGE_OK</p></body>
</html>
EOF

python3 -m http.server "$HTTP_PORT" --bind 0.0.0.0 \
    --directory "$HTTP_ROOT" >"$RESULT_DIR/http-server.log" 2>&1 &
HTTP_PID=$!
for _ in $(seq 1 50); do
    curl -fsS "http://127.0.0.1:$HTTP_PORT/index.html" >/dev/null 2>&1 && break
    kill -0 "$HTTP_PID" 2>/dev/null || fail "HTTP-сервер завершился"
    sleep 0.2
done
curl -fsS "http://127.0.0.1:$HTTP_PORT/preseed-ci.cfg" >/dev/null \
    || fail "preseed-ci.cfg не отдаётся по HTTP"
pass "CI HTTP-сервер и preseed доступны"

log "Live-загрузка точного ISO: BIOS"
start_qemu live-bios bios "" \
    -boot order=d,menu=off \
    -drive "file=$ISO_PATH,media=cdrom,readonly=on"
if ! wait_for_pattern "$CURRENT_SERIAL" OPKIOSK_RUNTIME_READY 420; then
    capture_screen "$RESULT_DIR/live-bios-failure"
    fail "Live ISO не достиг готовности в BIOS"
fi
capture_screen "$RESULT_DIR/live-bios-ready"
pass "Live ISO загрузился в BIOS до LightDM/Openbox/Chromium"
poweroff_vm

log "Live-загрузка точного ISO: UEFI"
LIVE_UEFI_VARS="$WORK_DIR/live-uefi-vars.fd"
cp -f "$OVMF_VARS_TEMPLATE" "$LIVE_UEFI_VARS"
start_qemu live-uefi uefi "$LIVE_UEFI_VARS" \
    -boot order=d,menu=off \
    -drive "file=$ISO_PATH,media=cdrom,readonly=on"
if ! wait_for_pattern "$CURRENT_SERIAL" OPKIOSK_RUNTIME_READY 480; then
    capture_screen "$RESULT_DIR/live-uefi-failure"
    fail "Live ISO не достиг готовности в UEFI"
fi
capture_screen "$RESULT_DIR/live-uefi-ready"
pass "Live ISO загрузился в UEFI до LightDM/Openbox/Chromium"
poweroff_vm

INSTALL_APPEND="auto=true priority=critical locale=en_US.UTF-8 keymap=us interface=auto hostname=op-kiosk domain=local url=$PRESEED_URL console=tty0 console=ttyS0,115200n8 DEBCONF_DEBUG=5"

install_and_test() {
    local firmware="$1"
    local disk="$WORK_DIR/op-kiosk-$firmware.qcow2"
    local vars_path=""
    local install_name="install-$firmware"

    log "Полная автоматическая установка: $firmware"
    rm -f "$disk"
    qemu-img create -f qcow2 "$disk" 10G \
        >"$RESULT_DIR/$install_name-qemu-img.log"

    if [[ "$firmware" == uefi ]]; then
        vars_path="$WORK_DIR/install-uefi-vars.fd"
        cp -f "$OVMF_VARS_TEMPLATE" "$vars_path"
    fi

    start_qemu "$install_name" "$firmware" "$vars_path" \
        -boot order=d,menu=off \
        -drive "file=$disk,if=virtio,format=qcow2,cache=unsafe,discard=unmap" \
        -drive "file=$ISO_PATH,media=cdrom,readonly=on" \
        -kernel "$EXTRACT_DIR/installer-vmlinuz" \
        -initrd "$EXTRACT_DIR/installer-initrd" \
        -append "$INSTALL_APPEND"

    local installer_pid="$CURRENT_QEMU_PID"
    if ! wait_for_pattern "$CURRENT_SERIAL" OPKIOSK_INSTALL_FINALIZE_PASS 2100; then
        capture_screen "$RESULT_DIR/$install_name-failure"
        fail "$firmware: Debian Installer не сообщил об успешной финализации"
    fi
    pass "$firmware: Debian Installer выполнил OP Kiosk finalizer"

    if ! wait_for_exit "$installer_pid" 300; then
        capture_screen "$RESULT_DIR/$install_name-no-poweroff"
        fail "$firmware: установщик не выключил виртуальную машину"
    fi
    CURRENT_QEMU_PID=""
    CURRENT_MONITOR=""
    CURRENT_SERIAL=""

    qemu-img check "$disk" >"$RESULT_DIR/$install_name-disk-check.txt" 2>&1 \
        || fail "$firmware: qemu-img check обнаружил повреждение диска"
    pass "$firmware: установленный виртуальный диск прошёл qemu-img check"

    local boot_index boot_name
    for boot_index in 1 2 3; do
        boot_name="installed-$firmware-cold-$boot_index"
        log "Холодная загрузка $boot_index/3: $firmware"

        start_qemu "$boot_name" "$firmware" "$vars_path" \
            -boot order=c,menu=off \
            -drive "file=$disk,if=virtio,format=qcow2,cache=unsafe,discard=unmap"

        if ! wait_for_pattern "$CURRENT_SERIAL" OPKIOSK_RUNTIME_READY_CI 480; then
            capture_screen "$RESULT_DIR/$boot_name-failure"
            fail "$firmware: холодная загрузка $boot_index не достигла проверенной страницы Chromium"
        fi
        capture_screen "$RESULT_DIR/$boot_name-ready"
        pass "$firmware: холодная загрузка $boot_index запустила LightDM/Openbox/Chromium и CI-страницу"

        hmp 'sendkey ctrl-alt-m' \
            || fail "$firmware: не удалось передать Ctrl+Alt+M"
        if ! wait_for_pattern "$CURRENT_SERIAL" OPKIOSK_MENU_OPENED 60; then
            capture_screen "$RESULT_DIR/$boot_name-menu-failure"
            fail "$firmware: сервисное меню не открылось по Ctrl+Alt+M"
        fi
        capture_screen "$RESULT_DIR/$boot_name-menu"
        pass "$firmware: Ctrl+Alt+M открыл сервисное меню"

        poweroff_vm
    done
}

install_and_test bios
install_and_test uefi

log "Итог"
pass "Полный цикл BIOS: ISO -> Debian Installer -> отключение ISO -> 3 холодные загрузки"
pass "Полный цикл UEFI: ISO -> Debian Installer -> отключение ISO -> 3 холодные загрузки"
pass "Chromium отрисовал CI-страницу, а Ctrl+Alt+M открыл сервисное меню"

printf '\nOP Kiosk OS full-cycle CI: PASS\n' | tee -a "$REPORT"
