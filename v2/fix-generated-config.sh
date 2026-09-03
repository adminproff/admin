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

TARGET="$WORK_DIR/config/includes.chroot/opt/op-kiosk/browser-supervisor.sh"
PACKAGE_LIST="$WORK_DIR/config/package-lists/op-kiosk.list.chroot"

[[ -s "$TARGET" ]] || {
    printf 'Не найден сгенерированный launcher: %s\n' "$TARGET" >&2
    exit 1
}
[[ -s "$PACKAGE_LIST" ]] || {
    printf 'Не найден список пакетов: %s\n' "$PACKAGE_LIST" >&2
    exit 1
}

python3 - "$TARGET" "$PACKAGE_LIST" <<'PYFIX'
from pathlib import Path
import sys

launcher = Path(sys.argv[1])
package_list = Path(sys.argv[2])
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
if "python3-minimal\n" not in packages:
    raise SystemExit("В списке пакетов отсутствует python3-minimal")
package_list.write_text(
    packages.replace("python3-minimal\n", "python3\n", 1),
    encoding="utf-8",
)
PYFIX

bash -n "$TARGET"
grep -Fxq python3 "$PACKAGE_LIST"

printf 'Сгенерированный Chromium launcher исправлен и проверен: %s\n' "$TARGET"
printf 'Для локальной offline-страницы включён полный пакет python3.\n'
