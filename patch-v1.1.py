#!/usr/bin/env python3
from __future__ import annotations

import re
from pathlib import Path

BUILD = Path("build.sh")
text = BUILD.read_text(encoding="utf-8")


def replace_once(old: str, new: str, description: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{description}: ожидалось одно совпадение, найдено {count}")
    text = text.replace(old, new, 1)


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


replace_once('VERSION="1.0"', 'VERSION="1.1"', "номер версии")
replace_once('--iso-volume "OPKIOSK_1_0"', '--iso-volume "OPKIOSK_1_1"', "метка ISO")

# Debian 13: исправляем имя PolicyKit-пакетов и добавляем средства надёжного X11-теста.
replace_once(
    "xserver-xorg-video-vesa\n",
    "xserver-xorg-video-vesa\nxserver-xorg-video-ati\n",
    "видеодрайвер ATI/Radeon",
)
replace_once(
    "x11-xserver-utils\n",
    "x11-xserver-utils\nx11-utils\nxvfb\n",
    "X11 диагностические пакеты",
)
replace_once(
    "sudo\npolicykit-1\ndbus-x11\n",
    "sudo\npolkitd\npkexec\ndbus-x11\n",
    "PolicyKit для Debian 13",
)

replace_heredoc(
    "config/includes.chroot/etc/openbox/rc.xml",
    r'''<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc">
  <resistance>
    <strength>10</strength>
    <screen_edge_strength>20</screen_edge_strength>
  </resistance>
  <focus>
    <focusNew>yes</focusNew>
    <followMouse>no</followMouse>
    <focusLast>yes</focusLast>
    <underMouse>no</underMouse>
    <focusDelay>200</focusDelay>
    <raiseOnFocus>no</raiseOnFocus>
  </focus>
  <placement>
    <policy>Smart</policy>
    <center>yes</center>
    <monitor>Primary</monitor>
    <primaryMonitor>1</primaryMonitor>
  </placement>
  <theme>
    <name>Clearlooks</name>
    <titleLayout>NLIMC</titleLayout>
    <keepBorder>no</keepBorder>
    <animateIconify>no</animateIconify>
  </theme>
  <desktops>
    <number>1</number>
    <firstdesk>1</firstdesk>
    <names><name>Kiosk</name></names>
    <popupTime>0</popupTime>
  </desktops>
  <keyboard>
    <chainQuitKey>C-g</chainQuitKey>
    <keybind key="C-A-F12">
      <action name="Execute"><command>/opt/op-kiosk/admin-menu.sh</command></action>
    </keybind>
    <keybind key="A-F4"><action name="None"/></keybind>
    <keybind key="C-A-Delete"><action name="None"/></keybind>
    <keybind key="A-Tab"><action name="None"/></keybind>
    <keybind key="W-r"><action name="None"/></keybind>
  </keyboard>
  <mouse>
    <dragThreshold>8</dragThreshold>
    <doubleClickTime>200</doubleClickTime>
    <screenEdgeWarpTime>0</screenEdgeWarpTime>
    <context name="Root">
      <mousebind button="Right" action="Press"><action name="None"/></mousebind>
      <mousebind button="Middle" action="Press"><action name="None"/></mousebind>
    </context>
    <context name="Client">
      <mousebind button="Right" action="Press"><action name="None"/></mousebind>
    </context>
  </mouse>
  <applications>
    <application class="*">
      <decor>no</decor>
      <maximized>yes</maximized>
    </application>
  </applications>
  <menu>
    <file>/etc/xdg/openbox/menu.xml</file>
    <hideDelay>200</hideDelay>
    <middle>no</middle>
    <submenuShowDelay>200</submenuShowDelay>
    <applicationIcons>no</applicationIcons>
    <manageDesktops>no</manageDesktops>
  </menu>
</openbox_config>''',
)

replace_heredoc(
    "config/includes.chroot/opt/op-kiosk/xinitrc",
    r'''#!/bin/bash
set -u

export HOME=/home/kiosk
export USER=kiosk
export LOGNAME=kiosk
export DISPLAY="${DISPLAY:-:0}"
export XDG_CONFIG_HOME="$HOME/.config"

UID_NOW="$(id -u)"
SYSTEM_RUNTIME="/run/user/$UID_NOW"
FALLBACK_RUNTIME="/tmp/op-kiosk-runtime-$UID_NOW"

if [[ -d "$SYSTEM_RUNTIME" && -w "$SYSTEM_RUNTIME" ]]; then
    export XDG_RUNTIME_DIR="$SYSTEM_RUNTIME"
else
    export XDG_RUNTIME_DIR="$FALLBACK_RUNTIME"
    install -d -m 0700 "$XDG_RUNTIME_DIR" 2>/dev/null || {
        mkdir -p "$XDG_RUNTIME_DIR"
        chmod 0700 "$XDG_RUNTIME_DIR" 2>/dev/null || true
    }
fi

export XDG_CACHE_HOME="$XDG_RUNTIME_DIR/cache"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" 2>/dev/null || true

setxkbmap -layout 'us,ru' -option 'grp:alt_shift_toggle' || true
xset s off || true
xset -dpms || true
xset s noblank || true
xsetroot -solid '#0b1220' || true
unclutter -idle 3 -root >/dev/null 2>&1 &

openbox --config-file /etc/openbox/rc.xml >/tmp/op-kiosk-openbox.log 2>&1 &

# Даём оконному менеджеру создать корневое окно до запуска Chromium.
for _ in $(seq 1 40); do
    pgrep -x openbox >/dev/null 2>&1 && break
    sleep 0.1
done
sleep 0.4

if command -v dbus-run-session >/dev/null 2>&1 && [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
    exec dbus-run-session -- /opt/op-kiosk/start-browser.sh
fi

exec /opt/op-kiosk/start-browser.sh''',
)

replace_heredoc(
    "config/includes.chroot/opt/op-kiosk/start-browser.sh",
    r'''#!/bin/bash
set -u

CONF=/var/lib/op-kiosk/kiosk.conf
LOCAL_PAGE='file:///opt/op-kiosk/html/index.html'
LOG=/tmp/op-kiosk-browser.log
FAIL_MARK=/tmp/op-kiosk-browser-error-shown

export HOME="${HOME:-/home/kiosk}"
export DISPLAY="${DISPLAY:-:0}"

UID_NOW="$(id -u)"
RUNTIME_CANDIDATE="${XDG_RUNTIME_DIR:-}"
if [[ -z "$RUNTIME_CANDIDATE" || ! -d "$RUNTIME_CANDIDATE" || ! -w "$RUNTIME_CANDIDATE" ]]; then
    RUNTIME_CANDIDATE="/tmp/op-kiosk-runtime-$UID_NOW"
fi
export XDG_RUNTIME_DIR="$RUNTIME_CANDIDATE"
mkdir -p "$XDG_RUNTIME_DIR" 2>/dev/null || true
chmod 0700 "$XDG_RUNTIME_DIR" 2>/dev/null || true

CACHE="$XDG_RUNTIME_DIR/chromium-cache"
PERSISTENT_PROFILE=/var/lib/op-kiosk/chromium
FALLBACK_PROFILE="$XDG_RUNTIME_DIR/chromium-profile"

mkdir -p "$CACHE" 2>/dev/null || true
if mkdir -p "$PERSISTENT_PROFILE" 2>/dev/null && [[ -w "$PERSISTENT_PROFILE" ]]; then
    PROFILE="$PERSISTENT_PROFILE"
else
    PROFILE="$FALLBACK_PROFILE"
    mkdir -p "$PROFILE" 2>/dev/null || true
fi

resolve_browser() {
    local configured="${1:-chromium}"
    if command -v "$configured" >/dev/null 2>&1; then
        command -v "$configured"
        return 0
    fi
    local candidate
    for candidate in chromium chromium-browser google-chrome-stable google-chrome; do
        if command -v "$candidate" >/dev/null 2>&1; then
            command -v "$candidate"
            return 0
        fi
    done
    return 1
}

show_error_once() {
    [[ -e "$FAIL_MARK" ]] && return 0
    : > "$FAIL_MARK"
    local tail_text
    tail_text="$(tail -n 18 "$LOG" 2>/dev/null || true)"
    zenity --error \
      --title='OP Kiosk OS — ошибка запуска' \
      --width=760 \
      --text="Chromium не запустился автоматически.\n\nЖурнал: $LOG\n\n$tail_text" \
      >/dev/null 2>&1 &
}

launch_browser() {
    local browser="$1"
    local url="$2"
    local proxy="$3"
    local no_sandbox="$4"
    local -a args

    # Удаляем только аварийные lock-файлы, не затрагивая настройки профиля.
    rm -f "$PROFILE"/SingletonLock "$PROFILE"/SingletonSocket "$PROFILE"/SingletonCookie 2>/dev/null || true

    args=(
      --kiosk
      --start-fullscreen
      --ozone-platform=x11
      --no-first-run
      --no-default-browser-check
      --noerrdialogs
      --disable-session-crashed-bubble
      --disable-infobars
      --disable-notifications
      --disable-component-update
      --disable-background-networking
      --disable-features=TranslateUI,MediaRouter,OptimizationHints
      --disable-dev-shm-usage
      --disable-gpu
      --disable-gpu-compositing
      --overscroll-history-navigation=0
      --disable-pinch
      --autoplay-policy=no-user-gesture-required
      --user-data-dir="$PROFILE"
      --disk-cache-dir="$CACHE"
      --password-store=basic
    )

    if [[ -n "$proxy" ]]; then
        args+=(--proxy-server="$proxy")
    fi

    if [[ "$no_sandbox" == yes ]]; then
        args+=(--no-sandbox)
    fi

    if [[ "${OPKIOSK_SMOKETEST:-0}" == 1 ]] || grep -qw 'opkiosk.smoketest' /proc/cmdline 2>/dev/null; then
        args+=(--remote-debugging-address=127.0.0.1 --remote-debugging-port=9222)
    fi

    {
        printf '\n[%s] Запуск: %q' "$(date -Is)" "$browser"
        printf ' %q' "${args[@]}" "$url"
        printf '\n'
    } >>"$LOG"

    local started pid rc elapsed
    started="$(date +%s)"
    "$browser" "${args[@]}" "$url" >>"$LOG" 2>&1 &
    pid=$!
    wait "$pid"
    rc=$?
    elapsed=$(( $(date +%s) - started ))
    printf '[%s] Chromium завершился: rc=%s, время=%ss\n' "$(date -Is)" "$rc" "$elapsed" >>"$LOG"

    if (( elapsed < 6 )); then
        return 111
    fi
    return "$rc"
}

: > "$LOG" 2>/dev/null || true

while true; do
    KIOSK_URL=''
    PROXY_URL=''
    BROWSER='chromium'
    source "$CONF" 2>/dev/null || true

    URL="${KIOSK_URL:-$LOCAL_PAGE}"
    PROXY="${PROXY_URL:-}"

    if ! BROWSER_PATH="$(resolve_browser "${BROWSER:-chromium}")"; then
        printf '[%s] Браузер не найден в PATH=%s\n' "$(date -Is)" "$PATH" >>"$LOG"
        show_error_once
        sleep 10
        continue
    fi

    launch_browser "$BROWSER_PATH" "$URL" "$PROXY" no
    rc=$?

    # На системах, где Chromium sandbox запрещён политикой ядра, делаем один
    # контролируемый повтор. Терминал работает под непривилегированным kiosk.
    if [[ $rc -eq 111 ]]; then
        printf '[%s] Повторный запуск с --no-sandbox после раннего завершения.\n' "$(date -Is)" >>"$LOG"
        launch_browser "$BROWSER_PATH" "$URL" "$PROXY" yes
        rc=$?
    fi

    [[ $rc -eq 111 ]] && show_error_once
    sleep 2
done''',
)

replace_heredoc(
    "config/includes.chroot/etc/systemd/system/op-kiosk-smoke.service",
    r'''[Unit]
Description=OP Kiosk OS browser smoke test
ConditionKernelCommandLine=opkiosk.smoketest
After=getty@tty1.service NetworkManager.service
Wants=getty@tty1.service NetworkManager.service

[Service]
Type=oneshot
ExecStart=/opt/op-kiosk/smoke-test.sh
TimeoutStartSec=120

[Install]
WantedBy=multi-user.target''',
)

# Добавляем проверку не только загрузки ядра, но и реально запущенного Chromium.
smoke_anchor = "cat > config/includes.chroot/etc/systemd/system/op-kiosk-smoke.service <<'EOF'"
smoke_pos = text.find(smoke_anchor)
if smoke_pos < 0:
    raise RuntimeError("Не найден smoke service после замены")
smoke_eof = text.find("\nEOF", smoke_pos)
if smoke_eof < 0:
    raise RuntimeError("Не найден конец smoke service")
smoke_eof += len("\nEOF")
smoke_script = r'''

cat > config/includes.chroot/opt/op-kiosk/smoke-test.sh <<'EOF'
#!/bin/bash
set -u

for _ in $(seq 1 100); do
    if curl -fsS --max-time 2 http://127.0.0.1:9222/json/list 2>/dev/null | grep -q 'OP Kiosk OS'; then
        echo OPKIOSK_BROWSER_OK >/dev/ttyS0 2>/dev/null || true
        systemctl poweroff
        exit 0
    fi
    sleep 1
done

echo OPKIOSK_BROWSER_FAILED >/dev/ttyS0 2>/dev/null || true
systemctl poweroff
exit 1
EOF'''
text = text[:smoke_eof] + smoke_script + text[smoke_eof:]

# В первой версии меню писалось не в тот системный каталог Openbox.
replace_once(
    "cat > /etc/openbox/menu.xml <<'EOT'",
    "mkdir -p /etc/xdg/openbox\ncat > /etc/xdg/openbox/menu.xml <<'EOT'",
    "путь меню Openbox",
)

BUILD.write_text(text, encoding="utf-8")
print("build.sh подготовлен для OP Kiosk OS 1.1")
