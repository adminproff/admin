#!/usr/bin/env bash
set -Eeuo pipefail

TARGET="${1:-}"
[[ -n "$TARGET" && -s "$TARGET" ]] || {
    echo "Использование: $0 /path/to/test-full-cycle.sh" >&2
    exit 2
}

python3 - "$TARGET" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")


def replace_once(old: str, new: str, description: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(
            f"{description}: ожидалось одно совпадение, найдено {count}"
        )
    text = text.replace(old, new, 1)


replace_once(
    '''for command_name in \\
    qemu-system-x86_64 qemu-img xorriso socat python3 curl grep sed awk timeout; do
''',
    '''for command_name in \\
    qemu-system-x86_64 qemu-img xorriso unsquashfs socat python3 curl grep sed awk timeout; do
''',
    "проверка наличия unsquashfs",
)

replace_once(
    '''    qemu-img create -f qcow2 "$disk" 10G \\
        >"$RESULT_DIR/$install_name-qemu-img.log"
''',
    '''    qemu-img create -f qcow2 "$disk" 8G \\
        >"$RESULT_DIR/$install_name-qemu-img.log"
    if ! qemu-img info --output=json "$disk" \\
        | jq -e '."virtual-size" == 8589934592' >/dev/null; then
        fail "$firmware: тестовый внутренний диск не равен 8 ГБ"
    fi
    pass "$firmware: установка проверяется на внутреннем диске ровно 8 ГБ"
''',
    "диск 8 ГБ",
)

replace_once(
    '''    start_qemu "$install_name" "$firmware" "$vars_path" \\
        -boot order=d,menu=off \\
        -drive "file=$disk,if=virtio,format=qcow2,cache=unsafe,discard=unmap" \\
        -drive "file=$ISO_PATH,media=cdrom,readonly=on" \\
        -kernel "$EXTRACT_DIR/installer-vmlinuz" \\
        -initrd "$EXTRACT_DIR/installer-initrd" \\
        -append "$INSTALL_APPEND"

    local installer_pid="$CURRENT_QEMU_PID"
''',
    '''    local install_media="$WORK_DIR/op-kiosk-install-media-$firmware.img"
    cp --reflink=auto --sparse=always "$ISO_PATH" "$install_media"
    chmod 0600 "$install_media"

    start_qemu "$install_name" "$firmware" "$vars_path" \\
        -boot order=d,menu=off \\
        -drive "file=$disk,if=virtio,format=qcow2,cache=unsafe,discard=unmap" \\
        -device qemu-xhci,id=xhci \\
        -drive "file=$install_media,if=none,id=installmedia,format=raw,cache=unsafe" \\
        -device usb-storage,drive=installmedia,bus=xhci.0,removable=true \\
        -kernel "$EXTRACT_DIR/installer-vmlinuz" \\
        -initrd "$EXTRACT_DIR/installer-initrd" \\
        -append "$INSTALL_APPEND"

    local installer_pid="$CURRENT_QEMU_PID"
    if ! wait_for_pattern "$CURRENT_SERIAL" \\
        'OPKIOSK_INSTALLER_SAFETY PASS' 180; then
        capture_screen "$RESULT_DIR/$install_name-safety-failure"
        fail "$firmware: установочный USB не был переведён в read-only до partman"
    fi
    pass "$firmware: Rufus-подобный USB-носитель защищён от записи до разметки"
''',
    "установка с Rufus-подобного USB и safety marker",
)

replace_once(
    '''pass "CI HTTP-сервер и preseed доступны"
''',
    '''grep -Fq 'op-kiosk-protect-install-media' "$HTTP_ROOT/preseed-ci.cfg" \\
    || fail "CI preseed не вызывает защиту установочного носителя"
pass "CI HTTP-сервер, preseed и защита установочного USB доступны"
''',
    "статическая проверка CI preseed",
)

replace_once(
    '''pass "Полный цикл BIOS: ISO -> Debian Installer -> отключение ISO -> 3 холодные загрузки"
pass "Полный цикл UEFI: ISO -> Debian Installer -> отключение ISO -> 3 холодные загрузки"
''',
    '''pass "Полный цикл BIOS: Rufus-подобный USB -> Debian Installer -> отключение USB -> 3 холодные загрузки"
pass "Полный цикл UEFI: Rufus-подобный USB -> Debian Installer -> отключение USB -> 3 холодные загрузки"
''',
    "итоговое описание USB-цикла",
)

path.write_text(text, encoding="utf-8")
PY

bash -n "$TARGET"
grep -Fq 'qemu-img create -f qcow2 "$disk" 8G' "$TARGET"
grep -Fq 'OPKIOSK_INSTALLER_SAFETY PASS' "$TARGET"
grep -Fq 'usb-storage,drive=installmedia' "$TARGET"
grep -Fq 'unsquashfs socat' "$TARGET"

printf 'Полный тест усилен: диск 8 ГБ, writable USB-копия ISO и обязательный safety marker.\n'
