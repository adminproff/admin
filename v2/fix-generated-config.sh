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
LAUNCHER="$CONFIG/includes.chroot/opt/op-kiosk/browser-supervisor.sh"
SESSION="$CONFIG/includes.chroot/opt/op-kiosk/session.sh"
ADMIN_MENU="$CONFIG/includes.chroot/opt/op-kiosk/admin-menu.sh"
PACKAGE_LIST="$CONFIG/package-lists/op-kiosk.list.chroot"
FINALIZER="$CONFIG/includes.chroot/usr/local/sbin/op-kiosk-finalize"
TMPFILES="$CONFIG/includes.chroot/etc/tmpfiles.d/op-kiosk.conf"
PRESEED="$CONFIG/binary_debian-installer/preseed.cfg"
PRESEED_COPY="$CONFIG/includes.installer/preseed.cfg"
PROTECT_SCRIPT="$CONFIG/includes.installer/usr/local/sbin/op-kiosk-protect-install-media"

for required in \
    "$LAUNCHER" "$SESSION" "$ADMIN_MENU" "$PACKAGE_LIST" \
    "$FINALIZER" "$TMPFILES" "$PRESEED" "$PRESEED_COPY"; do
    [[ -s "$required" ]] || {
        printf 'Не найден сгенерированный файл: %s\n' "$required" >&2
        exit 1
    }
done

python3 - \
    "$LAUNCHER" "$SESSION" "$ADMIN_MENU" "$PACKAGE_LIST" \
    "$FINALIZER" "$TMPFILES" "$PRESEED" "$PRESEED_COPY" \
    "$PROTECT_SCRIPT" <<'PYFIX'
from pathlib import Path
import sys

(
    launcher,
    session,
    admin_menu,
    package_list,
    finalizer,
    tmpfiles,
    preseed,
    preseed_copy,
    protect_script,
) = map(Path, sys.argv[1:])


def replace_exact(text: str, old: str, new: str, description: str, count: int = 1) -> str:
    actual = text.count(old)
    if actual != count:
        raise SystemExit(
            f"{description}: ожидалось совпадений {count}, найдено {actual}"
        )
    return text.replace(old, new, count)


launcher_text = launcher.read_text(encoding="utf-8")
launcher_text = replace_exact(
    launcher_text,
    '''urlencode() {
    python3 - "$1" <<'PY'
import sys
from urllib.parse import quote
print(quote(sys.argv[1], safe=''))
PY
}
''',
    '''urlencode() {
    python3 -c 'import sys; from urllib.parse import quote; print(quote(sys.argv[1], safe=""))' "$1"
}
''',
    "устранение вложенного heredoc в urlencode",
)
launcher_text = replace_exact(
    launcher_text,
    '''target_reachable() {
    local url="$1"
    local ignore_cert="$2"
    [[ -n "$url" ]] || return 1
    case "$url" in
        file://*)
            [[ -e "${url#file://}" ]]
            return
            ;;
        http://*|https://*)
            local -a curl_args
            curl_args=(-fsS -o /dev/null --connect-timeout 3 --max-time 5)
            [[ "$ignore_cert" == yes ]] && curl_args+=(-k)
            curl "${curl_args[@]}" "$url"
            return
            ;;
        *)
            return 1
            ;;
    esac
}
''',
    '''target_reachable() {
    local url="$1"
    local ignore_cert="$2"
    local proxy_url="${3:-}"
    [[ -n "$url" ]] || return 1
    case "$url" in
        file://*)
            [[ -e "${url#file://}" ]]
            return
            ;;
        http://*|https://*)
            local -a curl_args
            curl_args=(-sS -o /dev/null --connect-timeout 3 --max-time 5)
            [[ "$ignore_cert" == yes ]] && curl_args+=(-k)
            [[ -n "$proxy_url" ]] && curl_args+=(--proxy "$proxy_url")
            curl "${curl_args[@]}" "$url"
            return
            ;;
        *)
            return 1
            ;;
    esac
}
''',
    "поддержка proxy и HTTP-ответов в проверке доступности",
)
launcher_text = replace_exact(
    launcher_text,
    'target_reachable "$target_url" "$ignore_cert"',
    'target_reachable "$target_url" "$ignore_cert" "$proxy_url"',
    "передача proxy во внутренние проверки",
    count=2,
)
launcher_text = replace_exact(
    launcher_text,
    'target_reachable "$TARGET_URL" "$IGNORE_CERT"',
    'target_reachable "$TARGET_URL" "$IGNORE_CERT" "$PROXY"',
    "передача proxy в начальную проверку",
)
launcher.write_text(launcher_text, encoding="utf-8")

session_text = session.read_text(encoding="utf-8")
session_text = replace_exact(
    session_text,
    "setxkbmap -layout 'us,ru' -option 'grp:alt_shift_toggle' >/dev/null 2>&1 || true",
    "setxkbmap -layout 'us' >/dev/null 2>&1 || true",
    "фиксированная US-раскладка для служебных hotkey",
)
session.write_text(session_text, encoding="utf-8")

menu_text = admin_menu.read_text(encoding="utf-8")
menu_text = replace_exact(
    menu_text,
    '''check_password
serial OPKIOSK_MENU_OPENED

while true; do
''',
    '''check_password

if ci_mode; then
    zenity --info --title="$TITLE" --width=700 \\
        --text='CI: окно сервисного меню действительно отображено.' \\
        >/dev/null 2>&1 &
    ci_zenity_pid=$!
    for _ in $(seq 1 100); do
        if xdotool search --onlyvisible --name 'OP Kiosk OS' \\
            >/dev/null 2>&1; then
            serial OPKIOSK_MENU_OPENED
            wait "$ci_zenity_pid" 2>/dev/null || true
            exit 0
        fi
        kill -0 "$ci_zenity_pid" 2>/dev/null || break
        sleep 0.1
    done
    serial OPKIOSK_MENU_WINDOW_FAILED
    kill -TERM "$ci_zenity_pid" 2>/dev/null || true
    wait "$ci_zenity_pid" 2>/dev/null || true
    exit 1
fi

serial OPKIOSK_MENU_OPENED

while true; do
''',
    "проверка реально отображённого окна сервисного меню",
)
admin_menu.write_text(menu_text, encoding="utf-8")

packages = package_list.read_text(encoding="utf-8")
packages = replace_exact(
    packages,
    "systemd-sysv\n",
    "systemd-sysv\nsystemd-timesyncd\n",
    "добавление синхронизации времени",
)
packages = replace_exact(
    packages,
    "python3-minimal\n",
    "python3\n",
    "полный Python для локальной offline-страницы",
)
package_list.write_text(packages, encoding="utf-8")

finalizer_text = finalizer.read_text(encoding="utf-8")
finalizer_text = replace_exact(
    finalizer_text,
    '''systemctl enable NetworkManager.service >/dev/null 2>&1
systemctl enable lightdm.service >/dev/null 2>&1
''',
    '''systemctl enable NetworkManager.service >/dev/null 2>&1
systemctl enable systemd-timesyncd.service >/dev/null 2>&1 || true
systemctl enable lightdm.service >/dev/null 2>&1
''',
    "включение systemd-timesyncd",
)
finalizer_text = replace_exact(
    finalizer_text,
    '''check 'graphical.target is default' \\
    test "$(readlink -f /etc/systemd/system/default.target 2>/dev/null)" \\
        = /lib/systemd/system/graphical.target
''',
    '''check 'graphical.target is default' \\
    test "$(systemctl get-default 2>/dev/null)" = graphical.target
''',
    "проверка graphical.target с учётом usrmerge",
)
finalizer.write_text(finalizer_text, encoding="utf-8")

tmpfiles_text = tmpfiles.read_text(encoding="utf-8")
expected_tmpfiles = '''d /var/lib/op-kiosk 0750 1000 1000 -
d /var/lib/op-kiosk/chromium 0700 1000 1000 -
d /var/log/op-kiosk 0755 1000 1000 -
'''
replacement_tmpfiles = '''d /var/lib/op-kiosk 0750 kiosk kiosk -
d /var/lib/op-kiosk/chromium 0700 kiosk kiosk -
d /var/log/op-kiosk 0755 kiosk kiosk -
'''
if tmpfiles_text != expected_tmpfiles:
    raise SystemExit("Содержимое op-kiosk.conf tmpfiles отличается от ожидаемого")
tmpfiles.write_text(replacement_tmpfiles, encoding="utf-8")

protect_script.parent.mkdir(parents=True, exist_ok=True)
protect_script.write_text(
    '''#!/bin/sh
set -eu

log() {
    printf 'OP Kiosk OS installer safety: %s\\n' "$*" \\
        >>/var/log/syslog 2>/dev/null || true
    printf 'OPKIOSK_INSTALLER_SAFETY %s\\n' "$*" \\
        >/dev/ttyS0 2>/dev/null || true
}

source_device="$(findmnt -n -o SOURCE /cdrom 2>/dev/null || true)"
if [ -z "$source_device" ]; then
    source_device="$(mount 2>/dev/null | awk '$3=="/cdrom" {print $1; exit}')"
fi

case "$source_device" in
    /dev/*) ;;
    *)
        log "FAIL reason=installation-media-not-detected source=$source_device"
        exit 1
        ;;
esac

source_device="$(readlink -f "$source_device")"
base="$(basename "$source_device")"
protected_device="$source_device"

if [ -e "/sys/class/block/$base/partition" ]; then
    parent="$(basename "$(readlink -f "/sys/class/block/$base/..")")"
    [ -n "$parent" ] || {
        log "FAIL reason=parent-device-not-detected source=$source_device"
        exit 1
    }
    protected_device="/dev/$parent"
fi

[ -b "$protected_device" ] || {
    log "FAIL reason=not-a-block-device device=$protected_device"
    exit 1
}

blockdev --setro "$protected_device"
readonly_flag="$(blockdev --getro "$protected_device")"
[ "$readonly_flag" = 1 ] || {
    log "FAIL reason=read-only-verification-failed device=$protected_device"
    exit 1
}

printf '%s\\n' "$protected_device" >/run/op-kiosk-protected-install-media
log "PASS device=$protected_device source=$source_device"
exit 0
''',
    encoding="utf-8",
)

preseed_anchor = "d-i partman-auto/method string regular\n"
preseed_safety = (
    "d-i partman/early_command string "
    "/usr/local/sbin/op-kiosk-protect-install-media\n"
    + preseed_anchor
)
for path in (preseed, preseed_copy):
    value = path.read_text(encoding="utf-8")
    value = replace_exact(
        value,
        preseed_anchor,
        preseed_safety,
        f"добавление защиты установочного носителя в {path}",
    )
    path.write_text(value, encoding="utf-8")
PYFIX

chmod 0755 "$PROTECT_SCRIPT"

bash -n "$LAUNCHER"
bash -n "$SESSION"
bash -n "$ADMIN_MENU"
bash -n "$FINALIZER"
sh -n "$PROTECT_SCRIPT"
grep -Fxq python3 "$PACKAGE_LIST"
grep -Fxq systemd-timesyncd "$PACKAGE_LIST"
grep -Fxq 'd /var/lib/op-kiosk 0750 kiosk kiosk -' "$TMPFILES"
grep -Fq 'systemctl get-default' "$FINALIZER"
grep -Fq 'op-kiosk-protect-install-media' "$PRESEED"
grep -Fq 'OPKIOSK_INSTALLER_SAFETY' "$PROTECT_SCRIPT"
grep -Fq "setxkbmap -layout 'us'" "$SESSION"
grep -Fq 'xdotool search --onlyvisible' "$ADMIN_MENU"

printf 'Сгенерированный Chromium launcher исправлен и проверен.\n'
printf 'Проверка доступности рабочего URL учитывает proxy и любой HTTP-ответ.\n'
printf 'Для локальной offline-страницы включён полный пакет python3.\n'
printf 'Синхронизация времени systemd-timesyncd включена.\n'
printf 'Служебные hotkey закреплены за US-раскладкой.\n'
printf 'CI подтверждает фактическое окно сервисного меню через xdotool.\n'
printf 'Установочный носитель переводится в read-only до запуска partman.\n'
printf 'Проверка default target учитывает Debian usrmerge.\n'
printf 'Владельцы tmpfiles задаются по имени пользователя kiosk.\n'
