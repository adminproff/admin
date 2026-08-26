#!/usr/bin/env python3
from __future__ import annotations

import re
from pathlib import Path

BUILD = Path("build.sh")
DEFAULT_URL = "http://op-arkhbum.local:3080"
text = BUILD.read_text(encoding="utf-8")


def replace_heredoc(target: str, body: str) -> None:
    global text
    pattern = re.compile(
        rf"(cat > {re.escape(target)} <<'EOF'\n).*?(\nEOF)",
        flags=re.DOTALL,
    )
    text, count = pattern.subn(
        lambda match: match.group(1) + body.rstrip("\n") + match.group(2),
        text,
        count=1,
    )
    if count != 1:
        raise RuntimeError(f"Не найден heredoc для {target}")


def insert_before(anchor: str, block: str, description: str) -> None:
    global text
    count = text.count(anchor)
    if count != 1:
        raise RuntimeError(
            f"{description}: ожидалось одно совпадение, найдено {count}"
        )
    text = text.replace(anchor, block.rstrip("\n") + "\n\n" + anchor, 1)


# В предыдущем варианте был ошибочный адрес https://op.arkhbum.local.
old_url = "https://op.arkhbum.local"
url_count = text.count(old_url)
if url_count < 2:
    raise RuntimeError(
        f"URL: ожидалось не менее двух совпадений {old_url!r}, найдено {url_count}"
    )
text = text.replace(old_url, DEFAULT_URL)

# На терминале должна быть предсказуемая английская раскладка US без
# случайного переключения Alt+Shift во время работы оператора.
text = text.replace(
    "setxkbmap -layout 'us,ru' -option 'grp:alt_shift_toggle'",
    "setxkbmap -layout 'us'",
)

# Smoke-test загружает финальный SquashFS, поднимает X11/Openbox/Chromium и
# подтверждает через DevTools, что отрисована встроенная локальная страница.
# Он используется только в CI при параметре ядра opkiosk.smoketest.
replace_heredoc(
    "config/includes.chroot/opt/op-kiosk/smoke-test.sh",
    r'''#!/bin/bash
set -u

serial() {
    printf '%s\n' "$*" >/dev/ttyS0 2>/dev/null || true
    printf '%s\n' "$*"
}

serial OPKIOSK_SMOKE_STARTED

network_ok=0
for _ in $(seq 1 120); do
    if ip -4 route show default 2>/dev/null | grep -q '^default '; then
        serial OPKIOSK_NETWORK_OK
        network_ok=1
        break
    fi
    sleep 1
done

x11_ok=0
for _ in $(seq 1 180); do
    if [[ -S /tmp/.X11-unix/X0 ]]; then
        serial OPKIOSK_X11_OK
        x11_ok=1
        break
    fi
    sleep 1
done

openbox_ok=0
for _ in $(seq 1 120); do
    if pgrep -x openbox >/dev/null 2>&1; then
        serial OPKIOSK_OPENBOX_OK
        openbox_ok=1
        break
    fi
    sleep 1
done

browser_ok=0
for _ in $(seq 1 240); do
    json="$(curl -fsS --max-time 2 http://127.0.0.1:9222/json/list 2>/dev/null || true)"
    if printf '%s' "$json" | grep -q 'OP Kiosk OS' \
       && printf '%s' "$json" | grep -q 'file:///opt/op-kiosk/html/index.html'; then
        serial OPKIOSK_LOCAL_PAGE_OK
        serial OPKIOSK_BROWSER_OK
        browser_ok=1
        break
    fi
    sleep 1
done

if [[ $network_ok -eq 1 && $x11_ok -eq 1 && $openbox_ok -eq 1 && $browser_ok -eq 1 ]]; then
    serial OPKIOSK_SMOKE_PASS
    # Оставляем время GitHub Actions снять скриншот экрана.
    sleep 15
    systemctl poweroff
    exit 0
fi

serial OPKIOSK_SMOKE_FAILED
serial '--- ip address ---'
ip address >/dev/ttyS0 2>/dev/null || true
serial '--- ip route ---'
ip route >/dev/ttyS0 2>/dev/null || true
serial '--- lightdm ---'
tail -n 120 /var/log/lightdm/lightdm.log >/dev/ttyS0 2>/dev/null || true
serial '--- xorg ---'
tail -n 120 /var/log/Xorg.0.log >/dev/ttyS0 2>/dev/null || true
serial '--- session ---'
tail -n 120 /var/log/op-kiosk/session.log >/dev/ttyS0 2>/dev/null || true
serial '--- browser ---'
tail -n 180 /var/log/op-kiosk/browser.log >/dev/ttyS0 2>/dev/null || true
systemctl poweroff
exit 1''',
)

# Постоянная проверка обычной загрузки ничего не выключает и не подменяет URL.
# Она подтверждает, что реальный Chromium запущен именно с рабочим адресом.
insert_before(
    "cat > config/hooks/live/0100-op-kiosk.hook.chroot <<'EOF'",
    rf'''cat > config/includes.chroot/etc/systemd/system/op-kiosk-health.service <<'EOF'
[Unit]
Description=OP Kiosk OS normal boot readiness check
ConditionKernelCommandLine=!opkiosk.smoketest
After=lightdm.service NetworkManager.service
Wants=lightdm.service NetworkManager.service

[Service]
Type=oneshot
ExecStart=/opt/op-kiosk/health-check.sh
TimeoutStartSec=360

[Install]
WantedBy=graphical.target
EOF

cat > config/includes.chroot/opt/op-kiosk/health-check.sh <<'EOF'
#!/bin/bash
set -u

EXPECTED_URL='{DEFAULT_URL}'

serial() {{
    printf '%s\n' "$*" >/dev/ttyS0 2>/dev/null || true
    printf '%s\n' "$*"
}}

has_browser_with_url() {{
    local cmdline
    for cmdline in /proc/[0-9]*/cmdline; do
        [[ -r "$cmdline" ]] || continue
        if tr '\0' ' ' <"$cmdline" 2>/dev/null \
           | grep -Fq -- "$EXPECTED_URL"; then
            return 0
        fi
    done
    return 1
}}

serial OPKIOSK_HEALTH_STARTED
config_ok=0
network_ok=0
x11_ok=0
openbox_ok=0
browser_ok=0

for _ in $(seq 1 300); do
    if [[ $config_ok -eq 0 ]] \
       && grep -Fxq "KIOSK_URL=$EXPECTED_URL" /var/lib/op-kiosk/kiosk.conf 2>/dev/null; then
        serial OPKIOSK_CONFIG_URL_OK
        config_ok=1
    fi

    if [[ $network_ok -eq 0 ]] \
       && ip -4 route show default 2>/dev/null | grep -q '^default '; then
        serial OPKIOSK_NETWORK_OK
        network_ok=1
    fi

    if [[ $x11_ok -eq 0 && -S /tmp/.X11-unix/X0 ]]; then
        serial OPKIOSK_X11_OK
        x11_ok=1
    fi

    if [[ $openbox_ok -eq 0 ]] && pgrep -x openbox >/dev/null 2>&1; then
        serial OPKIOSK_OPENBOX_OK
        openbox_ok=1
    fi

    if [[ $browser_ok -eq 0 ]] && has_browser_with_url; then
        serial OPKIOSK_BROWSER_URL_OK
        serial OPKIOSK_BROWSER_OK
        browser_ok=1
    fi

    if [[ $config_ok -eq 1 && $network_ok -eq 1 && $x11_ok -eq 1 \
          && $openbox_ok -eq 1 && $browser_ok -eq 1 ]]; then
        serial OPKIOSK_RUNTIME_READY
        exit 0
    fi
    sleep 1
done

serial OPKIOSK_RUNTIME_FAILED
serial '--- processes ---'
ps auxww >/dev/ttyS0 2>/dev/null || true
serial '--- network ---'
ip address >/dev/ttyS0 2>/dev/null || true
ip route >/dev/ttyS0 2>/dev/null || true
serial '--- lightdm ---'
tail -n 120 /var/log/lightdm/lightdm.log >/dev/ttyS0 2>/dev/null || true
serial '--- xorg ---'
tail -n 120 /var/log/Xorg.0.log >/dev/ttyS0 2>/dev/null || true
serial '--- session ---'
tail -n 120 /var/log/op-kiosk/session.log >/dev/ttyS0 2>/dev/null || true
serial '--- browser ---'
tail -n 180 /var/log/op-kiosk/browser.log >/dev/ttyS0 2>/dev/null || true
exit 1
EOF''',
    "добавление health-check обычной загрузки",
)

needle = (
    "systemctl enable op-kiosk-smoke.service >/dev/null 2>&1 || true\n"
    "systemctl enable lightdm.service >/dev/null 2>&1 || true"
)
replacement = (
    "systemctl enable op-kiosk-smoke.service >/dev/null 2>&1 || true\n"
    "systemctl enable op-kiosk-health.service >/dev/null 2>&1 || true\n"
    "systemctl enable lightdm.service >/dev/null 2>&1 || true"
)
count = text.count(needle)
if count != 1:
    raise RuntimeError(
        f"включение health-check: ожидалось одно совпадение, найдено {count}"
    )
text = text.replace(needle, replacement, 1)

# Обязательные утверждения до начала многочасовой сборки.
required = [
    'VERSION="1.3"',
    DEFAULT_URL,
    "autologin-user=kiosk",
    "autologin-session=op-kiosk",
    "OPKIOSK_RUNTIME_READY",
    "OPKIOSK_SMOKE_PASS",
    "setxkbmap -layout 'us'",
]
for marker in required:
    if marker not in text:
        raise RuntimeError(f"После патча отсутствует обязательный маркер: {marker}")

BUILD.write_text(text, encoding="utf-8")
print("build.sh подготовлен для финальной проверяемой OP Kiosk OS 1.3")
