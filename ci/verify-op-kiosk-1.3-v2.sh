#!/usr/bin/env bash
set -Eeuo pipefail

# Непосредственная ссылка graphical.target.wants/lightdm.service не является
# обязательной для Debian: graphical.target уже запускает display-manager.service,
# а display-manager.service указывает на lightdm.service. Берём проверенный
# основной сценарий из неизменяемого коммита и удаляем только это ложное условие.
SOURCE_COMMIT="3076ff959bb4a771e4cf774151a8b989e13b6fa1"
SOURCE_URL="https://raw.githubusercontent.com/adminproff/admin/${SOURCE_COMMIT}/ci/verify-op-kiosk-1.3-v2.sh"
TMP_SCRIPT="$(mktemp --suffix=.sh)"

cleanup() {
    rm -f "$TMP_SCRIPT"
}
trap cleanup EXIT

curl -fsSL --retry 5 --retry-delay 2 "$SOURCE_URL" -o "$TMP_SCRIPT"

python3 - "$TMP_SCRIPT" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
needle = "    /etc/systemd/system/graphical.target.wants/lightdm.service \\\n"
count = text.count(needle)
if count != 1:
    raise RuntimeError(
        "Не удалось однозначно удалить ложную проверку LightDM: "
        f"совпадений {count}"
    )
path.write_text(text.replace(needle, "", 1), encoding="utf-8")
PY

bash -n "$TMP_SCRIPT"
exec bash "$TMP_SCRIPT" "$@"
