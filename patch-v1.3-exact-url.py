#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

BUILD = Path("build.sh")
WRONG_URL = "http://op-arkhbum.local:3080"
RIGHT_URL = "https://op.arkhbum.local"

text = BUILD.read_text(encoding="utf-8")
wrong_count = text.count(WRONG_URL)
if wrong_count < 2:
    raise RuntimeError(
        f"Ожидалось не менее двух временных URL {WRONG_URL!r}, найдено {wrong_count}"
    )

text = text.replace(WRONG_URL, RIGHT_URL)

required = [
    'VERSION="1.3"',
    'KIOSK_URL=https://op.arkhbum.local',
    "EXPECTED_URL='https://op.arkhbum.local'",
    'autologin-user=kiosk',
    'autologin-session=op-kiosk',
    'LOG_DIR=/var/log/op-kiosk',
    'SESSION_LOG="$LOG_DIR/session.log"',
    '"$LOG_DIR/openbox.log"',
    'LOG="$LOG_DIR/browser.log"',
    '/var/log/lightdm/lightdm.log',
    'OPKIOSK_RUNTIME_READY',
    'OPKIOSK_SMOKE_PASS',
]

for marker in required:
    if marker not in text:
        raise RuntimeError(f"После финального патча отсутствует обязательный маркер: {marker}")

if WRONG_URL in text:
    raise RuntimeError("В build.sh остался временный HTTP-адрес")

BUILD.write_text(text, encoding="utf-8")
print(
    "build.sh зафиксирован для OP Kiosk OS 1.3: "
    "https://op.arkhbum.local, LightDM, постоянные журналы"
)
