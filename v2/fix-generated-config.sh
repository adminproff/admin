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
PACKAGE_LIST="$CONFIG/package-lists/op-kiosk.list.chroot"
FINALIZER="$CONFIG/includes.chroot/usr/local/sbin/op-kiosk-finalize"
TMPFILES="$CONFIG/includes.chroot/etc/tmpfiles.d/op-kiosk.conf"

for required in "$LAUNCHER" "$PACKAGE_LIST" "$FINALIZER" "$TMPFILES"; do
    [[ -s "$required" ]] || {
        printf 'Не найден сгенерированный файл: %s\n' "$required" >&2
        exit 1
    }
done

python3 - "$LAUNCHER" "$PACKAGE_LIST" "$FINALIZER" "$TMPFILES" <<'PYFIX'
from pathlib import Path
import sys

launcher = Path(sys.argv[1])
package_list = Path(sys.argv[2])
finalizer = Path(sys.argv[3])
tmpfiles = Path(sys.argv[4])

text = launcher.read_text(encoding="utf-8")
old = '''urlencode() {
    python3 - "$1" <<'PY'
import sys
from urllib.parse import quote
print(quote(sys.argv[1], safe=''))
PY
}
'''
new = '''urlencode() {
    python3 -c 'import sys; from urllib.parse import quote; print(quote(sys.argv[1], safe=""))' "$1"
}
'''
count = text.count(old)
if count != 1:
    raise SystemExit(
        f"Ожидалось одно определение urlencode с вложенным heredoc, найдено: {count}"
    )
launcher.write_text(text.replace(old, new, 1), encoding="utf-8")

packages = package_list.read_text(encoding="utf-8")
if packages.count("python3-minimal\n") != 1:
    raise SystemExit("Ожидалась одна строка python3-minimal в списке пакетов")
package_list.write_text(
    packages.replace("python3-minimal\n", "python3\n", 1),
    encoding="utf-8",
)

finalizer_text = finalizer.read_text(encoding="utf-8")
old_check = '''check 'graphical.target is default' \\
    test "$(readlink -f /etc/systemd/system/default.target 2>/dev/null)" \\
        = /lib/systemd/system/graphical.target
'''
new_check = '''check 'graphical.target is default' \\
    test "$(systemctl get-default 2>/dev/null)" = graphical.target
'''
if finalizer_text.count(old_check) != 1:
    raise SystemExit("Не найдена ожидаемая проверка graphical.target")
finalizer.write_text(
    finalizer_text.replace(old_check, new_check, 1),
    encoding="utf-8",
)

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
PYFIX

bash -n "$LAUNCHER"
bash -n "$FINALIZER"
grep -Fxq python3 "$PACKAGE_LIST"
grep -Fxq 'd /var/lib/op-kiosk 0750 kiosk kiosk -' "$TMPFILES"
grep -Fq 'systemctl get-default' "$FINALIZER"

printf 'Сгенерированный Chromium launcher исправлен и проверен.\n'
printf 'Для локальной offline-страницы включён полный пакет python3.\n'
printf 'Проверка default target учитывает Debian usrmerge.\n'
printf 'Владельцы tmpfiles задаются по имени пользователя kiosk.\n'
