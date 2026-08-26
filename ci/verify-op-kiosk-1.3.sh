#!/usr/bin/env bash
set -Eeuo pipefail

ISO_INPUT="${1:?Укажите путь к ISO}"
OUT_INPUT="${2:-runtime-test}"
EXPECTED_URL="${EXPECTED_URL:-http://op-arkhbum.local:3080}"
TIMEOUT_NORMAL="${TIMEOUT_NORMAL:-720}"
TIMEOUT_SMOKE="${TIMEOUT_SMOKE:-720}"

ISO="$(readlink -f "$ISO_INPUT")"
OUT="$(mkdir -p "$OUT_INPUT" && cd "$OUT_INPUT" && pwd)"
ISO_TREE="$OUT/iso-tree"
ROOTFS="$OUT/rootfs"
REPORT="$OUT/verification-report.txt"

log() {
    printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

fail() {
    printf '\nОШИБКА: %s\n' "$*" >&2
    exit 1
}

need() {
    command -v "$1" >/dev/null 2>&1 || fail "Не найдена команда: $1"
}

for tool in \
    xorriso unsquashfs qemu-system-x86_64 socat sha256sum file \
    grep awk sed find stat identify convert; do
    need "$tool"
done

[[ -s "$ISO" ]] || fail "ISO отсутствует или пуст: $ISO"
rm -rf "$ISO_TREE" "$ROOTFS"
mkdir -p "$ISO_TREE"

log "Контрольная сумма и структура ISO"
sha256sum "$ISO" | tee "$OUT/iso.sha256"
file "$ISO" | tee "$OUT/iso-file-info.txt"
xorriso -indev "$ISO" -report_el_torito plain \
    >"$OUT/iso-el-torito-report.txt" 2>&1
xorriso -indev "$ISO" -toc \
    >"$OUT/iso-toc.txt" 2>&1
xorriso -osirrox on -indev "$ISO" -extract / "$ISO_TREE" \
    >"$OUT/iso-extract.log" 2>&1

[[ -s "$ISO_TREE/live/filesystem.squashfs" ]] \
    || fail "В ISO отсутствует /live/filesystem.squashfs"
[[ -n "$(find "$ISO_TREE" -type f -iname 'BOOTX64.EFI' -print -quit)" ]] \
    || fail "В ISO отсутствует UEFI-загрузчик BOOTX64.EFI"

log "Извлечение финального SquashFS"
unsquashfs -d "$ROOTFS" "$ISO_TREE/live/filesystem.squashfs" \
    >"$OUT/unsquashfs.log" 2>&1

log "Статическая проверка финальной live-системы"
for path in \
    /opt/op-kiosk/session.sh \
    /opt/op-kiosk/xinitrc \
    /opt/op-kiosk/start-browser.sh \
    /opt/op-kiosk/smoke-test.sh \
    /opt/op-kiosk/health-check.sh \
    /opt/op-kiosk/admin-menu.sh \
    /opt/op-kiosk/admin-terminal.sh \
    /usr/bin/chromium \
    /usr/sbin/lightdm; do
    [[ -x "$ROOTFS$path" ]] || fail "Нет исполняемого файла $path"
done

for path in \
    /etc/lightdm/lightdm.conf.d/50-op-kiosk.conf \
    /etc/systemd/system/op-kiosk-smoke.service \
    /etc/systemd/system/op-kiosk-health.service \
    /usr/share/xsessions/op-kiosk.desktop \
    /var/lib/op-kiosk/kiosk.conf; do
    [[ -f "$ROOTFS$path" ]] || fail "Нет файла $path"
done

[[ -L "$ROOTFS/etc/systemd/system/display-manager.service" ]] \
    || fail "display-manager.service не является ссылкой"
[[ -L "$ROOTFS/etc/systemd/system/default.target" ]] \
    || fail "default.target не является ссылкой"
[[ -e "$ROOTFS/etc/systemd/system/graphical.target.wants/lightdm.service" ]] \
    || fail "LightDM не включён в graphical.target"
[[ -e "$ROOTFS/etc/systemd/system/graphical.target.wants/op-kiosk-health.service" ]] \
    || fail "op-kiosk-health.service не включён"

readlink "$ROOTFS/etc/systemd/system/display-manager.service" \
    | tee "$OUT/display-manager-link.txt"
readlink "$ROOTFS/etc/systemd/system/default.target" \
    | tee "$OUT/default-target-link.txt"

grep -Fx "KIOSK_URL=$EXPECTED_URL" "$ROOTFS/var/lib/op-kiosk/kiosk.conf"
grep -F 'autologin-user=kiosk' \
    "$ROOTFS/etc/lightdm/lightdm.conf.d/50-op-kiosk.conf"
grep -F 'autologin-session=op-kiosk' \
    "$ROOTFS/etc/lightdm/lightdm.conf.d/50-op-kiosk.conf"
grep -F "EXPECTED_URL='$EXPECTED_URL'" \
    "$ROOTFS/opt/op-kiosk/health-check.sh"
grep -F "setxkbmap -layout 'us'" "$ROOTFS/opt/op-kiosk/xinitrc"
grep -F 'OPKIOSK_RUNTIME_READY' "$ROOTFS/opt/op-kiosk/health-check.sh"
grep -F 'OPKIOSK_SMOKE_PASS' "$ROOTFS/opt/op-kiosk/smoke-test.sh"

for script in \
    "$ROOTFS/opt/op-kiosk/session.sh" \
    "$ROOTFS/opt/op-kiosk/xinitrc" \
    "$ROOTFS/opt/op-kiosk/start-browser.sh" \
    "$ROOTFS/opt/op-kiosk/smoke-test.sh" \
    "$ROOTFS/opt/op-kiosk/health-check.sh" \
    "$ROOTFS/opt/op-kiosk/admin-menu.sh" \
    "$ROOTFS/opt/op-kiosk/admin-terminal.sh"; do
    bash -n "$script"
done

for package in \
    chromium lightdm network-manager linux-image-amd64 \
    firmware-amd-graphics firmware-realtek firmware-iwlwifi; do
    grep -A3 -m1 -E "^Package: ${package}$" "$ROOTFS/var/lib/dpkg/status" \
        | grep -q '^Status: install ok installed$' \
        || fail "Пакет $package не подтверждён как установленный"
done

find "$ROOTFS/lib/firmware" -type f -print -quit | grep -q . \
    || fail "Каталог firmware пуст"

capture_screen() {
    local monitor="$1"
    local prefix="$2"
    local ppm="$OUT/${prefix}.ppm"
    local png="$OUT/${prefix}.png"
    local dimensions deviation

    for _ in $(seq 1 20); do
        [[ -S "$monitor" ]] && break
        sleep 0.5
    done
    [[ -S "$monitor" ]] || fail "Не появился QEMU monitor: $monitor"

    rm -f "$ppm" "$png"
    printf 'screendump %s\n' "$ppm" \
        | socat -t 10 - "UNIX-CONNECT:$monitor" >/dev/null 2>&1 || true

    for _ in $(seq 1 20); do
        [[ -s "$ppm" ]] && break
        sleep 0.5
    done
    [[ -s "$ppm" ]] || fail "QEMU не создал скриншот $ppm"

    convert "$ppm" "$png"
    [[ -s "$png" ]] || fail "Не создан PNG $png"
    dimensions="$(identify -format '%w %h' "$png")"
    read -r width height <<<"$dimensions"
    (( width >= 640 && height >= 480 )) \
        || fail "Недостаточный размер скриншота: $dimensions"

    deviation="$(convert "$png" -format '%[fx:standard_deviation]' info:)"
    awk -v value="$deviation" 'BEGIN { exit !(value > 0.005) }' \
        || fail "Скриншот выглядит одноцветным: deviation=$deviation"
    printf '%s: %sx%s, deviation=%s\n' "$prefix" "$width" "$height" "$deviation" \
        | tee -a "$OUT/screenshot-checks.txt"
}

stop_qemu() {
    local pid="$1"
    kill "$pid" 2>/dev/null || true
    for _ in $(seq 1 20); do
        kill -0 "$pid" 2>/dev/null || return 0
        sleep 0.25
    done
    kill -9 "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
}

wait_for_markers() {
    local pid="$1"
    local serial="$2"
    local timeout="$3"
    shift 3
    local -a markers=("$@")
    local elapsed marker all_ok

    for elapsed in $(seq 1 "$timeout"); do
        all_ok=1
        for marker in "${markers[@]}"; do
            if ! grep -Fq "$marker" "$serial" 2>/dev/null; then
                all_ok=0
                break
            fi
        done
        [[ $all_ok -eq 1 ]] && return 0

        if ! kill -0 "$pid" 2>/dev/null; then
            return 1
        fi
        sleep 1
    done
    return 1
}

run_normal_boot() {
    local mode="$1"
    local prefix="normal-${mode,,}"
    local serial="$OUT/${prefix}-serial.log"
    local qemu_log="$OUT/${prefix}-qemu.log"
    local monitor="$OUT/${prefix}-monitor.sock"
    local vars_copy=""
    local code=""
    local vars=""
    local pid
    local -a firmware_args=()

    : >"$serial"
    : >"$qemu_log"
    rm -f "$monitor"

    if [[ "$mode" == UEFI ]]; then
        code="$(find /usr/share/OVMF /usr/share/qemu -type f \
            \( -name 'OVMF_CODE_4M.fd' -o -name 'OVMF_CODE.fd' \) \
            2>/dev/null | sort | head -1)"
        vars="$(find /usr/share/OVMF /usr/share/qemu -type f \
            \( -name 'OVMF_VARS_4M.fd' -o -name 'OVMF_VARS.fd' \) \
            2>/dev/null | sort | head -1)"
        [[ -s "$code" && -s "$vars" ]] || fail "Не найдены OVMF CODE/VARS"
        vars_copy="$OUT/${prefix}-OVMF_VARS.fd"
        cp "$vars" "$vars_copy"
        firmware_args=(
            -drive "if=pflash,format=raw,readonly=on,file=$code"
            -drive "if=pflash,format=raw,file=$vars_copy"
        )
    fi

    log "Полная загрузка финального ISO: $mode"
    qemu-system-x86_64 \
        -name "op-kiosk-1.3-$prefix" \
        -machine q35,accel=tcg \
        -cpu max \
        -smp 2 \
        -m 3072 \
        "${firmware_args[@]}" \
        -boot order=d,menu=off \
        -drive "file=$ISO,media=cdrom,readonly=on,format=raw" \
        -device e1000,netdev=net0 \
        -netdev user,id=net0 \
        -vga std \
        -display none \
        -serial "file:$serial" \
        -monitor "unix:$monitor,server=on,wait=off" \
        -no-reboot \
        >"$qemu_log" 2>&1 &
    pid=$!

    if ! wait_for_markers "$pid" "$serial" "$TIMEOUT_NORMAL" \
        OPKIOSK_CONFIG_URL_OK \
        OPKIOSK_NETWORK_OK \
        OPKIOSK_X11_OK \
        OPKIOSK_OPENBOX_OK \
        OPKIOSK_BROWSER_URL_OK \
        OPKIOSK_RUNTIME_READY; then
        tail -n 1200 "$serial" || true
        cat "$qemu_log" || true
        stop_qemu "$pid"
        fail "$mode: финальный ISO не достиг состояния OPKIOSK_RUNTIME_READY"
    fi

    sleep 3
    capture_screen "$monitor" "$prefix-screen"
    stop_qemu "$pid"
    tail -n 400 "$serial" >"$OUT/${prefix}-serial-tail.log" || true
}

run_smoke_boot() {
    local kernel initrd serial qemu_log monitor pid
    kernel="$(find "$ISO_TREE/live" -maxdepth 1 -type f -name 'vmlinuz*' \
        | sort | head -1)"
    initrd="$(find "$ISO_TREE/live" -maxdepth 1 -type f -name 'initrd*' \
        | sort | head -1)"
    [[ -s "$kernel" && -s "$initrd" ]] \
        || fail "Не найдены kernel/initrd в финальном ISO"

    serial="$OUT/smoke-serial.log"
    qemu_log="$OUT/smoke-qemu.log"
    monitor="$OUT/smoke-monitor.sock"
    : >"$serial"
    : >"$qemu_log"
    rm -f "$monitor"

    log "Загрузка финального SquashFS и проверка фактической отрисовки Chromium"
    qemu-system-x86_64 \
        -name op-kiosk-1.3-render-smoke \
        -machine q35,accel=tcg \
        -cpu max \
        -smp 2 \
        -m 3072 \
        -kernel "$kernel" \
        -initrd "$initrd" \
        -append "boot=live components live-media=/dev/sr0 username=kiosk hostname=op-kiosk locales=ru_RU.UTF-8 keyboard-layouts=us opkiosk.smoketest console=ttyS0,115200n8 console=tty0 loglevel=4 systemd.show_status=true" \
        -drive "file=$ISO,media=cdrom,readonly=on,format=raw" \
        -device e1000,netdev=net0 \
        -netdev user,id=net0 \
        -vga std \
        -display none \
        -serial "file:$serial" \
        -monitor "unix:$monitor,server=on,wait=off" \
        -no-reboot \
        >"$qemu_log" 2>&1 &
    pid=$!

    if ! wait_for_markers "$pid" "$serial" "$TIMEOUT_SMOKE" \
        OPKIOSK_NETWORK_OK \
        OPKIOSK_X11_OK \
        OPKIOSK_OPENBOX_OK \
        OPKIOSK_LOCAL_PAGE_OK \
        OPKIOSK_BROWSER_OK \
        OPKIOSK_SMOKE_PASS; then
        tail -n 1200 "$serial" || true
        cat "$qemu_log" || true
        stop_qemu "$pid"
        fail "Chromium не подтвердил отрисовку встроенной страницы"
    fi

    capture_screen "$monitor" "smoke-local-page-screen"
    stop_qemu "$pid"
    tail -n 500 "$serial" >"$OUT/smoke-serial-tail.log" || true
}

run_normal_boot BIOS
run_normal_boot UEFI
run_smoke_boot

ISO_SHA="$(sha256sum "$ISO" | awk '{print $1}')"
ISO_SIZE="$(stat -c %s "$ISO")"

cat >"$REPORT" <<EOF
OP Kiosk OS 1.3 — отчёт автоматической проверки
Дата UTC: $(date -u '+%Y-%m-%dT%H:%M:%SZ')
ISO: $(basename "$ISO")
Размер: $ISO_SIZE байт
SHA-256: $ISO_SHA
Рабочий URL: $EXPECTED_URL

ISO9660 / El Torito: PASS
UEFI BOOTX64.EFI: PASS
Финальный SquashFS: PASS
LightDM autologin kiosk: PASS
Openbox session: PASS
NetworkManager и маршрут DHCP в QEMU: PASS
Chromium с рабочим URL при обычной BIOS-загрузке ISO: PASS
Chromium с рабочим URL при обычной UEFI-загрузке ISO: PASS
Фактическая отрисовка встроенной страницы Chromium через DevTools: PASS
Скриншот BIOS: PASS
Скриншот UEFI: PASS
Скриншот Chromium smoke-test: PASS

Граница проверки:
Внутренний сервер $EXPECTED_URL недоступен из GitHub Actions, поэтому проверяется
точная передача этого URL в Chromium, а отрисовка Chromium подтверждается на
встроенной локальной странице. Физическая проверка на конкретном HP t530
возможна только после записи образа на USB и загрузки самого терминала.
EOF

cat "$REPORT"
