#!/usr/bin/env bash
set -Eeuo pipefail

WORK_DIR=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --work-dir)
            WORK_DIR="$2"
            shift 2
            ;;
        *)
            printf 'Неизвестный аргумент: %s\n' "$1" >&2
            exit 2
            ;;
    esac
done

[[ -n "$WORK_DIR" ]] || {
    echo 'Не задан --work-dir' >&2
    exit 2
}

CONFIG="$WORK_DIR/config"
LIVE_CONF="$CONFIG/includes.chroot/etc/live/config.conf.d/10-op-kiosk.conf"
FINALIZER="$CONFIG/includes.chroot/usr/local/sbin/op-kiosk-finalize"
PRESEED="$CONFIG/binary_debian-installer/preseed.cfg"
PRESEED_COPY="$CONFIG/includes.installer/preseed.cfg"

for required in "$LIVE_CONF" "$FINALIZER" "$PRESEED" "$PRESEED_COPY"; do
    [[ -s "$required" ]] || {
        printf 'Не найден сгенерированный файл: %s\n' "$required" >&2
        exit 1
    }
done

python3 - "$LIVE_CONF" "$FINALIZER" "$PRESEED" "$PRESEED_COPY" <<'PY'
from pathlib import Path
import sys

live_conf, finalizer, preseed, preseed_copy = map(Path, sys.argv[1:])


def replace_once(path: Path, old: str, new: str, description: str) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(
            f"{description}: ожидалось одно совпадение в {path}, найдено {count}"
        )
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


replace_once(
    live_conf,
    'LIVE_USER_DEFAULT_GROUPS="audio cdrom video render input netdev plugdev"',
    'LIVE_USER_DEFAULT_GROUPS="audio cdrom video render input netdev plugdev dialout"',
    "добавление dialout live-пользователю",
)

replace_once(
    finalizer,
    'for group in audio cdrom video render input netdev plugdev; do',
    'for group in audio cdrom video render input netdev plugdev dialout; do',
    "добавление dialout установленному пользователю",
)

uefi_line = 'grub-efi-amd64 grub2/force_efi_extra_removable boolean true\n'
for path in (preseed, preseed_copy):
    text = path.read_text(encoding="utf-8")
    if uefi_line in text:
        continue
    anchor = 'd-i grub-installer/bootdev string default\n'
    count = text.count(anchor)
    if count != 1:
        raise SystemExit(
            f"UEFI removable fallback: ожидалось одно совпадение в {path}, найдено {count}"
        )
    path.write_text(text.replace(anchor, anchor + uefi_line, 1), encoding="utf-8")
PY

grep -Fq 'plugdev dialout' "$LIVE_CONF"
grep -Fq 'plugdev dialout; do' "$FINALIZER"
grep -Fxq 'grub-efi-amd64 grub2/force_efi_extra_removable boolean true' "$PRESEED"
grep -Fxq 'grub-efi-amd64 grub2/force_efi_extra_removable boolean true' "$PRESEED_COPY"
bash -n "$FINALIZER"

printf 'Пользователь kiosk добавлен в dialout для проверяемых serial-маркеров.\n'
printf 'Debian Installer настроен устанавливать резервный UEFI loader EFI/BOOT/BOOTX64.EFI.\n'
