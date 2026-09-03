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
[[ -s "$TARGET" ]] || {
    printf 'Не найден сгенерированный launcher: %s\n' "$TARGET" >&2
    exit 1
}

python3 - "$TARGET" <<'PYFIX'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

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

text = text.replace(old, new, 1)
path.write_text(text, encoding="utf-8")
PYFIX

bash -n "$TARGET"
printf 'Сгенерированный Chromium launcher исправлен и проверен: %s\n' "$TARGET"
