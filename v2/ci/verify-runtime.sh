#!/usr/bin/env bash
set -Eeuo pipefail

ISO="${1:?Укажите ISO}"
WORK="${2:-runtime-test}"
TIMEOUT_LIVE="${TIMEOUT_LIVE:-600}"
TIMEOUT_INSTALL="${TIMEOUT_INSTALL:-2400}"
TIMEOUT_INSTALLED="${TIMEOUT_INSTALLED:-600}"

ISO="$(readlink -f "$ISO")"
mkdir -p "$WORK"
WORK="$(readlink -f "$WORK")"

log() { printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }
die() { echo "ОШИБКА: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Не найдена команда: $1"; }
for cmd in qemu-system-x86_64 qemu-img xorriso socat timeout grep awk sed sha256sum; do need "$cmd"; done
[[ -s "$ISO" ]] || die "ISO отсутствует: $ISO"

wait_marker() {
    local file="$1" marker="$2" timeout_seconds="$3"
    timeout "$timeout_seconds" bash -c '
        file="$1"; marker="$2"
        while true; do
            [[ -f "$file" ]] && grep -Fq "$marker" "$file" && exit 0
            sleep 1
        done
    ' _ "$file" "$marker" || {
        echo "Не дождались маркера: $marker" >&2
        tail -n 240 "$file" 2>/dev/null || true
        return 1
    }
}

stop_vm() {
    local pid="$1" monitor="$2"
    if [[ -S "$monitor" ]]; then
        printf 'system_powerdown\n' | socat - UNIX-CONNECT:"$monitor" >/dev/null 2>&1 || true
        for _ in $(seq 1 30); do
            kill -0 "$pid" 2>/dev/null || return 0
            sleep 1
        done
        printf 'quit\n' | socat - UNIX-CONNECT:"$monitor" >/dev/null 2>&1 || true
    fi
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
}

find_ovmf() {
    local candidate
    for candidate in /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd /usr/share/edk2/x64/OVMF_CODE.fd; do
        [[ -f "$candidate" ]] && { printf '%s\n' "$candidate"; return 0; }
    done
    return 1
}

find_ovmf_vars() {
    local candidate
    for candidate in /usr/share/OVMF/OVMF_VARS_4M.fd /usr/share/OVMF/OVMF_VARS.fd /usr/share/edk2/x64/OVMF_VARS.fd; do
        [[ -f "$candidate" ]] && { printf '%s\n' "$candidate"; return 0; }
    done
    return 1
}

static_checks() {
    log "Статическая проверка ISO"
    file "$ISO" | tee "$WORK/file.txt"
    xorriso -indev "$ISO" -report_el_torito plain >"$WORK/el-torito.txt" 2>&1
    grep -Eq 'El Torito|boot' "$WORK/el-torito.txt"
    rm -rf "$WORK/extract"
    mkdir -p "$WORK/extract"
    for path in /live/filesystem.squashfs /live/vmlinuz /live/initrd.img /ci-preseed.cfg; do
        xorriso -osirrox on -indev "$ISO" -extract "$path" "$WORK/extract/$(basename "$path")" >/dev/null 2>&1 || die "В ISO отсутствует $path"
    done
    local install_kernel install_initrd
    install_kernel="$(xorriso -indev "$ISO" -find / -type f -name 'vmlinuz' -print 2>/dev/null | awk '/install|installer/{print; exit}')"
    install_initrd="$(xorriso -indev "$ISO" -find / -type f \( -name 'initrd.gz' -o -name 'initrd' \) -print 2>/dev/null | awk '/install|installer/{print; exit}')"
    [[ -n "$install_kernel" && -n "$install_initrd" ]] || die "Не найдены ядро/initrd Debian Installer"
    printf '%s\n' "$install_kernel" >"$WORK/installer-kernel-path.txt"
    printf '%s\n' "$install_initrd" >"$WORK/installer-initrd-path.txt"
    xorriso -osirrox on -indev "$ISO" -extract "$install_kernel" "$WORK/extract/installer-vmlinuz" >/dev/null 2>&1
    xorriso -osirrox on -indev "$ISO" -extract "$install_initrd" "$WORK/extract/installer-initrd" >/dev/null 2>&1
    test -s "$WORK/extract/installer-vmlinuz"
    test -s "$WORK/extract/installer-initrd"
}

run_live() {
    local firmware="$1" tag="$2"
    local serial="$WORK/${tag}-live.serial.log"
    local monitor="$WORK/${tag}-live.monitor.sock"
    local qlog="$WORK/${tag}-live.qemu.log"
    rm -f "$serial" "$monitor" "$qlog"
    local -a fw_args=()
    if [[ "$firmware" == uefi ]]; then
        local code vars_template vars
        code="$(find_ovmf)" || die "OVMF_CODE не найден"
        vars_template="$(find_ovmf_vars)" || die "OVMF_VARS не найден"
        vars="$WORK/${tag}-live-vars.fd"
        cp "$vars_template" "$vars"
        fw_args=(-drive "if=pflash,format=raw,readonly=on,file=$code" -drive "if=pflash,format=raw,file=$vars")
    fi
    log "Live-загрузка: $firmware"
    qemu-system-x86_64 -machine q35,accel=tcg -m 2048 -smp 2 -vga std -display none "${fw_args[@]}" -cdrom "$ISO" -boot d -nic user,model=virtio-net-pci -serial "file:$serial" -monitor "unix:$monitor,server=on,wait=off" -no-reboot >"$qlog" 2>&1 &
    local pid=$!
    wait_marker "$serial" OPKIOSK_LIVE_READY "$TIMEOUT_LIVE"
    wait_marker "$serial" OPKIOSK_NETWORK_OK "$TIMEOUT_LIVE"
    printf 'sendkey ctrl-alt-m\n' | socat - UNIX-CONNECT:"$monitor" >/dev/null
    wait_marker "$serial" OPKIOSK_MENU_STARTED 60
    printf 'screendump %s\n' "$WORK/${tag}-live.ppm" | socat - UNIX-CONNECT:"$monitor" >/dev/null || true
    stop_vm "$pid" "$monitor"
}

install_and_boot() {
    local firmware="$1" tag="$2"
    local disk="$WORK/${tag}-disk.qcow2"
    local serial="$WORK/${tag}-install.serial.log"
    local monitor="$WORK/${tag}-install.monitor.sock"
    local qlog="$WORK/${tag}-install.qemu.log"
    local vars=''
    rm -f "$disk" "$serial" "$monitor" "$qlog"
    qemu-img create -f qcow2 "$disk" 8G >/dev/null
    local -a fw_args=()
    if [[ "$firmware" == uefi ]]; then
        local code vars_template
        code="$(find_ovmf)" || die "OVMF_CODE не найден"
        vars_template="$(find_ovmf_vars)" || die "OVMF_VARS не найден"
        vars="$WORK/${tag}-install-vars.fd"
        cp "$vars_template" "$vars"
        fw_args=(-drive "if=pflash,format=raw,readonly=on,file=$code" -drive "if=pflash,format=raw,file=$vars")
    fi
    log "Автоматическая установка Debian Live Installer: $firmware"
    qemu-system-x86_64 -machine q35,accel=tcg -m 3072 -smp 2 -display none "${fw_args[@]}" -kernel "$WORK/extract/installer-vmlinuz" -initrd "$WORK/extract/installer-initrd" -append "auto=true priority=critical preseed/file=/cdrom/ci-preseed.cfg locale=en_US.UTF-8 console=ttyS0,115200n8 --- quiet" -cdrom "$ISO" -drive "file=$disk,if=virtio,format=qcow2" -nic user,model=virtio-net-pci -serial "file:$serial" -monitor "unix:$monitor,server=on,wait=off" -no-reboot >"$qlog" 2>&1 &
    local pid=$!
    wait_marker "$serial" OPKIOSK_INSTALL_FINALIZE_PASS "$TIMEOUT_INSTALL"
    for _ in $(seq 1 180); do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
    if kill -0 "$pid" 2>/dev/null; then stop_vm "$pid" "$monitor"; else wait "$pid" 2>/dev/null || true; fi
    for boot_no in 1 2 3; do
        local boot_serial="$WORK/${tag}-installed-${boot_no}.serial.log"
        local boot_monitor="$WORK/${tag}-installed-${boot_no}.monitor.sock"
        local boot_qlog="$WORK/${tag}-installed-${boot_no}.qemu.log"
        rm -f "$boot_serial" "$boot_monitor" "$boot_qlog"
        local -a boot_fw_args=()
        if [[ "$firmware" == uefi ]]; then
            local code
            code="$(find_ovmf)"
            boot_fw_args=(-drive "if=pflash,format=raw,readonly=on,file=$code" -drive "if=pflash,format=raw,file=$vars")
        fi
        log "Холодная загрузка установленного диска: $firmware, цикл $boot_no/3"
        qemu-system-x86_64 -machine q35,accel=tcg -m 2048 -smp 2 -vga std -display none "${boot_fw_args[@]}" -drive "file=$disk,if=virtio,format=qcow2" -nic user,model=virtio-net-pci -serial "file:$boot_serial" -monitor "unix:$boot_monitor,server=on,wait=off" -no-reboot >"$boot_qlog" 2>&1 &
        local boot_pid=$!
        wait_marker "$boot_serial" OPKIOSK_INSTALLED_READY "$TIMEOUT_INSTALLED"
        wait_marker "$boot_serial" OPKIOSK_NETWORK_OK "$TIMEOUT_INSTALLED"
        if [[ $boot_no -eq 1 ]]; then
            printf 'sendkey ctrl-alt-m\n' | socat - UNIX-CONNECT:"$boot_monitor" >/dev/null
            wait_marker "$boot_serial" OPKIOSK_MENU_STARTED 60
            printf 'screendump %s\n' "$WORK/${tag}-installed.ppm" | socat - UNIX-CONNECT:"$boot_monitor" >/dev/null || true
        fi
        stop_vm "$boot_pid" "$boot_monitor"
    done
}

static_checks
run_live bios bios
run_live uefi uefi
install_and_boot bios bios
install_and_boot uefi uefi

cat >"$WORK/verification-report.txt" <<EOF_REPORT
OP Kiosk OS 2.0 — полный CI-цикл
================================
ISO: $ISO
SHA-256: $(sha256sum "$ISO" | awk '{print $1}')
PASS — ISO9660/El Torito структура присутствует.
PASS — filesystem.squashfs, live kernel/initrd и ci-preseed.cfg присутствуют.
PASS — Debian Installer kernel/initrd присутствуют.
PASS — Live BIOS и UEFI запускают LightDM, X11, Openbox и Chromium.
PASS — Ctrl+Alt+M вызывает сервисное меню в live-режиме.
PASS — BIOS и UEFI установка на пустой 8-ГБ диск завершена Debian Live Installer.
PASS — После отключения ISO установленный диск выполнил три холодные загрузки в BIOS и UEFI.
PASS — На установленной системе запущены LightDM, X11, Openbox, Chromium и DHCP.
PASS — Ctrl+Alt+M вызывает сервисное меню после установки.
EOF_REPORT
cat "$WORK/verification-report.txt"
